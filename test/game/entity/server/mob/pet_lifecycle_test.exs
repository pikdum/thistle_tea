defmodule ThistleTea.Game.Entity.Server.Mob.PetLifecycleTest do
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
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PetLoyalty
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.WorldRef

  setup [:build_pet]

  describe "child_spec/1" do
    test "suspension snapshots final progress without restarting the supervised pet", %{pet: pet, guid: guid} do
      pet = PetLoyalty.initialize(pet, %PetProgress{level: 49, loyalty: 4, loyalty_points: 12_345, training_points: 45})
      {:ok, pid} = World.start_entity(pet)
      ref = Process.monitor(pid)

      assert {:ok, 166_500, false,
              %PetProgress{level: 49, xp: 123, loyalty: 4, loyalty_points: 12_345, training_points: 45}, :defensive} =
               Entity.call(guid, :suspend_hunter_pet)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert MobServer.child_spec(pet).restart == :temporary
      refute Entity.online?(guid)
    end
  end

  describe "broken loyalty lifecycle" do
    test "removes the retained bond, client controls, and supervised process", %{pet: pet, guid: guid, owner: owner} do
      {:ok, pid} = World.start_entity(pet)
      ref = Process.monitor(pid)
      state = attach_owner(pet, pid)
      broken = PetLoyalty.change(pet, -1_001)
      EventSink.emit_pending(broken, Context.new(pid))
      assert_receive %Effects.PetBroke{source_guid: ^guid, target_guid: ^owner} = effect

      assert {:noreply, detached, {:continue, :maybe_broadcast_update}} = PlayerServer.handle_info(effect, state)
      assert Companion.relationship(detached.character).status == :none
      assert detached.companion_monitor == nil
      assert detached.character.unit.summon == 0
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetBroken{}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetSpells{pet_guid: 0}}}
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
      refute Entity.online?(guid)
      assert PlayerServer.handle_info(effect, detached) == {:noreply, detached}
    end

    test "suspension racing a broken bond cannot retain or restore it", %{pet: pet, guid: guid} do
      broken = PetLoyalty.change(pet, -1_001)
      {:ok, pid} = World.start_entity(%{broken | internal: %{broken.internal | events: []}})
      state = attach_owner(pet, pid)
      suspended = CompanionOwner.suspend(state)
      assert Companion.relationship(suspended.character).status == :none
      assert suspended.companion_monitor == nil
      refute Entity.online?(guid)
    end

    test "uses the explicit entity context when its owner is absent", %{pet: pet, owner: owner} do
      Entity.unregister(owner)
      broken = PetLoyalty.change(pet, -1_001)
      parent = self()
      receiver = spawn(fn -> receive do: (message -> send(parent, {:forwarded, message})) end)
      EventSink.emit_pending(broken, Context.new(receiver))
      assert_receive {:forwarded, :pet_stop}
      refute_receive :pet_stop, 0
    end

    test "ignores notifications from replaced pets and after logout", %{pet: pet} do
      state = attach_owner(pet, self())
      effect = %Effects.PetBroke{source_guid: pet.object.guid + 1, target_guid: pet.internal.pet.owner_guid}
      assert PlayerServer.handle_info(effect, state) == {:noreply, state}
      assert PlayerServer.handle_info(effect, %State{}) == {:noreply, %State{}}
    end
  end

  defp attach_owner(pet, pid) do
    character = %Character{
      object: %Object{guid: pet.internal.pet.owner_guid},
      unit: %Unit{health: 100, auras: []},
      player: %Player{},
      internal: %Internal{world: pet.internal.world}
    }

    CompanionOwner.attach(%State{guid: character.object.guid, character: character}, %Attachment{
      kind: :hunter_pet,
      entity_ref: %EntityRef{guid: pet.object.guid, entry: 2960, spell_id: 1515},
      pid: pid,
      spells: []
    })
  end

  defp build_pet(_context) do
    guid = Guid.runtime(:pet, 2960)
    owner = System.unique_integer([:positive]) + 10_000_000
    Entity.register(owner)

    pet = %Mob{
      object: %Object{guid: guid, entry: 2960},
      unit: %Unit{
        health: 100,
        max_health: 100,
        level: 49,
        power5: 166_500,
        pet_experience: 123,
        pet_loyalty: 1,
        auras: []
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: WorldRef.open(451),
        pet: %Pet{owner_guid: owner, kind: :hunter, profile: :combat},
        creature: %Creature{},
        spawn: %Spawn{},
        spellbook: %{}
      }
    }

    on_exit(fn -> if Entity.online?(guid), do: World.stop_entity(guid) end)
    %{pet: pet, guid: guid, owner: owner}
  end
end
