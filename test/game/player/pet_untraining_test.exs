defmodule ThistleTea.Game.Player.PetUntrainingTest do
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
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.PetUntraining
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Gossip
  alias ThistleTea.Game.World.Loader.PetTraining
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:build_state]

  describe "confirm/2" do
    test "quotes the current pet without charging or clearing abilities", %{state: state, trainer: trainer, pet: pet} do
      assert PetUntraining.available?(state.character, trainer)
      offered = PetUntraining.confirm(state, trainer)
      assert offered.pet_unlearn_offer == %PetUntraining.Offer{pet_guid: pet, cost: 1_000}
      assert offered.character == state.character
      assert offered.gossip_menu_options == []
      assert map_size(:sys.get_state(Entity.pid(pet)).internal.spellbook) == 3
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgGossipComplete{}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetUnlearnConfirm{pet_guid: ^pet, cost: 1_000}}}
    end

    test "requires an eligible owner and a nearby live pet trainer", %{state: state, trainer: trainer} do
      refute PetUntraining.available?(put_in(state.character.unit.class, 9), trainer)
      assert PetUntraining.confirm(put_in(state.character.unit.health, 0), trainer).pet_unlearn_offer == nil
      SpatialHash.update(:mobs, trainer, WorldRef.open(451), 5.01, 0.0, 0.0)
      assert PetUntraining.confirm(state, trainer).pet_unlearn_offer == nil
      SpatialHash.update(:mobs, trainer, WorldRef.instance(451, 1), 0.0, 0.0, 0.0)
      assert PetUntraining.confirm(state, trainer).pet_unlearn_offer == nil
      SpatialHash.update(:mobs, trainer, WorldRef.open(451), 2.0, 0.0, 0.0)
      Metadata.update(trainer, %{alive?: false})
      assert PetUntraining.confirm(state, trainer).pet_unlearn_offer == nil
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetUnlearnConfirm{}}}, 0
    end
  end

  describe "complete/2" do
    test "charges once, projects the empty bar, and retains reset history on suspension", %{
      state: state,
      trainer: trainer,
      pet: pet
    } do
      completed = state |> PetUntraining.confirm(trainer) |> PetUntraining.complete(pet)
      assert completed.character.player.coinage == 9_000
      assert completed.pet_unlearn_offer == nil
      progress = completed.character.internal.companion.progress
      assert progress.spells == []
      assert progress.training_points == 49
      assert progress.last_untrain_cost == 1_000
      assert is_integer(progress.last_untrain_at)
      assert completed.character.internal.companion.autocast == MapSet.new()
      assert CharacterStore.get(state.character.id).internal.companion.progress == progress
      assert PetUntraining.complete(completed, pet) == completed
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetSpells{pet_guid: ^pet, spells: spells}}}
      assert length(spells) == 2

      offered = PetUntraining.confirm(completed, trainer)
      assert offered.pet_unlearn_offer.cost == 5_000
      assert {:ok, _happiness, false, ^progress, :defensive, _health} = Entity.call(pet, :suspend_hunter_pet)
      refute Entity.online?(pet)
      assert Metadata.get(pet) == nil
      assert World.position(pet) == nil
    end

    test "leaves abilities and payment intact when funds are insufficient", %{state: state, trainer: trainer, pet: pet} do
      state = put_in(state.character.player.coinage, 999)
      completed = state |> PetUntraining.confirm(trainer) |> PetUntraining.complete(pet)
      assert completed.character == state.character
      assert completed.pet_unlearn_offer == nil
      assert map_size(:sys.get_state(Entity.pid(pet)).internal.spellbook) == 3
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgBuyFailed{error: :not_enough_money}}}
    end

    test "rejects forged and stale pet confirmations", %{state: state, trainer: trainer, pet: pet} do
      assert PetUntraining.complete(state, pet) == state
      offered = PetUntraining.confirm(state, trainer)
      assert PetUntraining.complete(offered, pet + 1) == state

      character =
        Companion.activate(offered.character, :hunter_pet, %EntityRef{guid: pet + 1, entry: 69, spell_id: 1515})

      replaced = %{offered | character: character}
      assert PetUntraining.complete(replaced, pet).character == replaced.character
      assert map_size(:sys.get_state(Entity.pid(pet)).internal.spellbook) == 3
    end
  end

  defp build_state(_context) do
    owner = System.unique_integer([:positive, :monotonic]) + 10_000_000
    trainer = Guid.from_low_guid(:mob, 777_001, owner)
    pet_guid = Guid.runtime(:pet, 69)
    Entity.register(owner)
    family = Map.new([300, 301], &{&1, %Spell{id: &1, attributes: MapSet.new([:passive])}})
    :ets.insert(PetTraining, {{:family_passives, 999}, family})
    :ets.insert(Gossip, {{:trainer, 777_001}, %{type: 3, class: 3}})
    Metadata.put(trainer, %{alive?: true, npc_flags: 0x10})
    SpatialHash.update(:mobs, trainer, WorldRef.open(451), 2.0, 0.0, 0.0)

    character = %Character{
      id: owner,
      account_id: 1,
      object: %Object{guid: owner},
      unit: %Unit{health: 100, class: 3, race: 4, level: 49},
      player: %Player{coinage: 10_000},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(451)}
    }

    character = Companion.activate(character, :hunter_pet, %EntityRef{guid: pet_guid, entry: 69, spell_id: 1515})
    Presence.enter(character, %{alive?: true, faction_template: 1})

    pet = %Mob{
      object: %Object{guid: pet_guid, entry: 69},
      unit: %Unit{health: 100, max_health: 100, level: 49, power5: 800_000, pet_loyalty: 2, auras: []},
      movement_block: character.movement_block,
      internal: %Internal{
        world: character.internal.world,
        pet: %Pet{
          owner_guid: owner,
          kind: :hunter,
          profile: :combat,
          training_points: 44,
          autocast: MapSet.new([100]),
          family_spells: MapSet.new([300, 301])
        },
        creature: %Creature{family: 999},
        spawn: %Spawn{temporary?: true},
        spellbook: Map.put(family, 100, %Spell{id: 100})
      }
    }

    {:ok, _pid} = World.start_entity(pet)

    on_exit(fn ->
      World.stop_entity(pet_guid)
      Metadata.delete(trainer)
      Metadata.delete(owner)
      SpatialHash.remove(:mobs, trainer)
      SpatialHash.remove(:players, owner)
      :ets.delete(PetTraining, {:family_passives, 999})
      :ets.delete(Gossip, {:trainer, 777_001})
    end)

    %{state: %State{ready: true, guid: owner, character: character}, trainer: trainer, pet: pet_guid}
  end
end
