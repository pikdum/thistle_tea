defmodule ThistleTea.Game.Player.PetStableTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.PetProgress
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PetNaming
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Pets
  alias ThistleTea.Game.Player.PetStable
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:build_state]

  describe "authorized?/2" do
    test "requires a ready living hunter and a nearby live stable master", %{state: state, master: master} do
      assert PetStable.authorized?(state, master)
      refute PetStable.authorized?(%{state | ready: false}, master)
      refute PetStable.authorized?(put_in(state.character.unit.health, 0), master)
      refute PetStable.authorized?(put_in(state.character.unit.class, 9), master)
      refute PetStable.authorized?(put_in(state.character.internal.in_combat, true), master)
      refute PetStable.authorized?(state, state.guid)
      Metadata.update(master, %{alive?: false})
      refute PetStable.authorized?(state, master)
      Metadata.update(master, %{alive?: true, npc_flags: 0})
      refute PetStable.authorized?(state, master)
    end

    test "revalidates distance and world on every request", %{state: state, master: master} do
      SpatialHash.update(:mobs, master, WorldRef.open(451), 5.01, 0.0, 0.0)
      assert PetStable.buy(state, master, price_lookup: fn _ -> 500 end) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgStableResult{result: 6}}}
      SpatialHash.update(:mobs, master, WorldRef.instance(451, 1), 0.0, 0.0, 0.0)
      refute PetStable.authorized?(state, master)
      Metadata.delete(master)
      refute PetStable.authorized?(state, master)
    end
  end

  describe "buy/3" do
    test "retains purchased slots and charges with client feedback", %{state: state, master: master} do
      bought = PetStable.buy(state, master, price_lookup: fn _ -> 500 end)
      assert bought.character.player.coinage == 0
      assert bought.character.internal.pet_stable.slots == 1
      assert CharacterStore.get(state.character.id).internal.pet_stable.slots == 1
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgStableResult{result: 10}}}
      assert PetStable.buy(bought, master, price_lookup: fn _ -> 50_000 end) == bought
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgStableResult{result: 1}}}
    end
  end

  describe "transfer/4" do
    test "retains a committed name through live suspension and stable storage", %{
      state: state,
      master: master,
      pet: pet
    } do
      pet = PetNaming.initialize(pet, nil)
      {:ok, pid} = World.start_entity(pet)
      state = CompanionOwner.attach(state, attachment(pet, pid))
      state = put_in(state.character.internal.pet_stable.slots, 1)
      guid = pet.object.guid

      assert Pets.rename(%{state | ready: false}, guid, "Fang") == %{state | ready: false}
      assert Pets.rename(state, guid + 1, "Fang") == state
      assert Entity.call(guid, {:rename_pet, state.guid + 1, "Fang"}) == {:error, :unavailable}
      assert Pets.rename(state, guid, "Bad Name") == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetNameInvalid{}}}

      named = Pets.rename(state, guid, "Fang")
      identity = named.character.internal.companion.name
      assert identity.name == "Fang"
      assert CharacterStore.get(state.character.id).internal.companion.name == identity
      assert %{name: "Fang", pet_name_timestamp: timestamp} = Metadata.get(guid)
      assert timestamp == identity.timestamp
      assert Pets.rename(named, guid, "Claw") == named
      assert Entity.call(guid, {:rename_pet, state.guid, "Claw"}) == {:error, :unavailable}

      stored = PetStable.transfer(named, master, :store)
      assert stored.character.internal.pet_stable.pets[1].name == identity
      assert CharacterStore.get(state.character.id).internal.pet_stable.pets[1].name == identity
      refute Entity.online?(guid)
    end

    test "captures final live state and rejects late updates and attachments", %{state: state, master: master, pet: pet} do
      {:ok, pid} = World.start_entity(pet)
      attachment = attachment(pet, pid)
      state = CompanionOwner.attach(state, attachment)
      state = put_in(state.character.internal.pet_stable.slots, 1)
      ref = Process.monitor(pid)
      stored = PetStable.transfer(state, master, :store)
      saved = stored.character.internal.pet_stable.pets[1]
      assert saved.happiness == 800_000
      assert saved.health == 73
      assert saved.progress.xp == 123
      assert saved.progress.training_points == 17
      assert saved.reaction_state == :passive
      assert stored.character.internal.companion.status == :none
      assert stored.companion_monitor == nil
      assert CharacterStore.get(state.character.id).internal.pet_stable.pets[1] == saved
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      refute Entity.online?(pet.object.guid)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgStableResult{result: 8}}}
      assert PlayerServer.handle_info(attachment, stored) == {:noreply, stored}

      event = %Effects.PetProgressChanged{
        source_guid: pet.object.guid,
        target_guid: state.guid,
        progress: %PetProgress{level: 1}
      }

      assert PlayerServer.handle_info(event, stored) == {:noreply, stored}
      assert CompanionOwner.process_down(stored, ref) == :stale
    end

    test "failed retrieval leaves both current pet and stable unchanged", %{state: state, master: master, pet: pet} do
      {:ok, pid} = World.start_entity(pet)
      state = CompanionOwner.attach(state, attachment(pet, pid))
      state = with_stabled_pet(state, 77)
      failed = PetStable.transfer(state, master, {:swap, 77}, build_pet: fn _, _ -> nil end)
      assert failed == state
      assert Process.alive?(pid)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgStableResult{result: 6}}}

      failed =
        PetStable.transfer(state, master, {:swap, 77},
          build_pet: fn _, _ -> pet end,
          start_pet: fn _ -> {:error, :failed} end
        )

      assert failed == state
      assert Process.alive?(pid)
    end

    test "retrieving a dead pet does not summon or resurrect it", %{state: state, master: master} do
      state =
        state
        |> with_stabled_pet(77)
        |> put_in(
          [
            Access.key(:character),
            Access.key(:internal),
            Access.key(:pet_stable),
            Access.key(:pets),
            1,
            Access.key(:dead?)
          ],
          true
        )

      retrieved =
        PetStable.transfer(state, master, {:retrieve, 77}, build_pet: fn _, _ -> flunk("dead pet was summoned") end)

      assert retrieved.character.internal.companion.dead?
      assert retrieved.character.internal.companion.pet_number == 77
      assert retrieved.character.internal.pet_stable.pets == %{}
      assert retrieved.character.unit.summon == 0
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgStableResult{result: 9}}}
    end

    test "retrieval owns the replacement before queued attachment and permits immediate storage", %{
      state: state,
      master: master,
      pet: pet
    } do
      state = with_stabled_pet(state, 77)

      retrieved =
        PetStable.transfer(state, master, {:retrieve, 77},
          build_pet: fn _, _ -> pet end,
          start_pet: &World.start_entity/1
        )

      assert Companion.active_guid(retrieved.character) == pet.object.guid
      assert retrieved.character.internal.companion.pet_number == 77
      assert retrieved.companion_monitor.pid == Entity.pid(pet.object.guid)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetNameQueryResponse{pet_number: 77, name: "Boar"}}}
      assert_receive %Attachment{} = pending
      stored = PetStable.transfer(retrieved, master, :store)
      assert stored.character.internal.pet_stable.pets[1].pet_number == 77
      refute Entity.online?(pet.object.guid)
      assert PlayerServer.handle_info(pending, stored) == {:noreply, stored}
    end
  end

  describe "Pets.abandon/2" do
    test "removes only the current bond, process, metadata, and client controls", %{state: state, pet: pet} do
      {:ok, pid} = World.start_entity(PetNaming.initialize(pet, nil))
      state = state |> CompanionOwner.attach(attachment(pet, pid)) |> with_stabled_pet(77)
      state = Pets.rename(state, pet.object.guid, "Fang")
      guid = pet.object.guid
      ref = Process.monitor(pid)
      assert Pets.abandon(state, guid + 1) == state
      assert Pets.abandon(%{state | ready: false}, guid) == %{state | ready: false}

      abandoned = Pets.abandon(state, guid)
      assert abandoned.character.internal.companion.status == :none
      assert abandoned.character.internal.companion.name == nil
      assert abandoned.character.internal.pet_stable == state.character.internal.pet_stable
      assert abandoned.companion_monitor == nil
      assert abandoned.character.unit.summon == 0
      assert CharacterStore.get(state.character.id).internal.companion.status == :none
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetSpells{pet_guid: 0}}}
      assert Metadata.get(guid) == nil
      assert World.position(guid) == nil
      assert Pets.abandon(abandoned, guid) == abandoned
      assert PlayerServer.handle_info(attachment(pet, pid), abandoned) == {:noreply, abandoned}
    end
  end

  defp with_stabled_pet(state, number) do
    companion = %ThistleTea.Game.Entity.Data.Companion{
      kind: :hunter_pet,
      status: {:suspended, 69, 1515},
      pet_number: number,
      happiness: 700_000,
      progress: %PetProgress{level: 49, xp: 50}
    }

    put_in(state.character.internal.pet_stable, %ThistleTea.Game.Entity.Data.PetStable{
      slots: 1,
      pets: %{1 => companion}
    })
  end

  defp attachment(pet, pid) do
    %Attachment{
      kind: :hunter_pet,
      entity_ref: %EntityRef{guid: pet.object.guid, entry: 69, spell_id: 1515},
      pid: pid,
      spells: [],
      progress: %PetProgress{level: 49}
    }
  end

  defp build_state(_context) do
    id = System.unique_integer([:positive, :monotonic])
    owner = Guid.from_low_guid(:player, id)
    master = Guid.from_low_guid(:mob, 11_069, id)
    pet_guid = Guid.from_low_guid(:pet, 69, id)
    Entity.register(owner)
    Metadata.put(master, %{alive?: true, npc_flags: 0x2000})
    SpatialHash.update(:mobs, master, WorldRef.open(451), 2.0, 0.0, 0.0)
    SpatialHash.update(:players, owner, WorldRef.open(451), 0.0, 0.0, 0.0)

    character = %Character{
      id: id,
      account_id: 1,
      object: %Object{guid: owner},
      unit: %Unit{health: 100, class: 3, race: 4, level: 49, summon: 0},
      player: %Player{coinage: 500},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(451)}
    }

    pet = %Mob{
      object: %Object{guid: pet_guid},
      unit: %Unit{
        health: 73,
        max_health: 100,
        level: 49,
        power5: 800_000,
        pet_experience: 123,
        pet_loyalty: 2,
        auras: []
      },
      movement_block: character.movement_block,
      internal: %Internal{
        name: "Boar",
        world: WorldRef.open(451),
        pet: %Pet{owner_guid: owner, kind: :hunter, profile: :combat, training_points: 17, reaction_state: :passive},
        creature: %Creature{},
        spawn: %Spawn{temporary?: true},
        spellbook: %{}
      }
    }

    on_exit(fn ->
      World.stop_entity(pet_guid)
      Metadata.delete(master)
      Metadata.delete(owner)
      SpatialHash.remove(:mobs, master)
      SpatialHash.remove(:players, owner)
    end)

    Presence.enter(character, %{alive?: true, faction_template: 1})

    %{state: %State{ready: true, guid: owner, character: character}, master: master, pet: pet}
  end
end
