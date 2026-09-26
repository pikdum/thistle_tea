defmodule ThistleTea.Game.Entity.Logic.AI.BT.PetTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet, as: PetBT
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.AIEnvironment
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @now 10_000

  describe "tree/0" do
    test "an idle pet finishes preparing its self buff before following" do
      state = pet_beside_owner(1)
      spell = %Spell{id: 10, cast_time_ms: 1_000, mana_cost: 0, effects: []}
      creature = %Internal.Creature{spells: [%CreatureSpell{spell_id: spell.id, cast_target: :self}]}

      state = %{
        state
        | unit: %{state.unit | health: 100, max_health: 100, level: 10, auras: []},
          internal: %{
            state.internal
            | creature: creature,
              spellbook: %{spell.id => spell},
              pet: %{state.internal.pet | autocast: MapSet.new([spell.id])}
          }
      }

      assert {{:running, 1_000, :casting}, casting} = BT.tick(PetBT.tree(), state, Context.new(@now))
      assert casting.internal.casting.spell.id == spell.id
      refute Enum.any?(casting.internal.events, &is_struct(&1, Effects.DespawnSelf))
    end

    test "aggressive pets ignore neutral and obstructed units and acquire hostile players" do
      state = pet_beside_owner(1)

      state = %{
        state
        | unit: %{state.unit | health: 100},
          internal: %{state.internal | pet: %{state.internal.pet | reaction_state: :aggressive}}
      }

      source = %FactionTemplate{id: 1, faction: 1, faction_group: 3, friend_group: 2, enemy_group: 12}
      enemy = %FactionTemplate{id: 17, faction: 15, faction_group: 8, enemy_group: 1}
      neutral = %FactionTemplate{id: 7, faction: 7, faction_group: 0, enemy_group: 0}
      player_guid = Guid.from_low_guid(:player, 700)
      neutral_guid = Guid.from_low_guid(:mob, 7, 700)
      obstructed_guid = Guid.from_low_guid(:mob, 17, 701)

      entities = %{
        state.object.guid => %Observation{guid: state.object.guid, metadata: %{faction_template: source}},
        neutral_guid => %Observation{guid: neutral_guid, metadata: %{faction_template: neutral, alive?: true}},
        obstructed_guid => %Observation{
          guid: obstructed_guid,
          metadata: %{faction_template: enemy, alive?: true},
          line_of_sight?: false
        },
        player_guid => %Observation{guid: player_guid, metadata: %{faction_template: enemy, alive?: true, pvp?: true}}
      }

      perception =
        Perception.new(@now, {world(), 0.0, 2.0, 0.0}, entities, %{
          mobs: [{neutral_guid, 1.0}, {obstructed_guid, 2.0}],
          players: [{player_guid, 3.0}]
        })

      assert {:success, attacking} = BT.tick(PetBT.tree(), state, Context.new(@now, perception: perception))
      assert attacking.unit.target == player_guid
      assert attacking.internal.in_combat
    end
  end

  describe "follow_owner/3" do
    test "stays put while a stationary owner turns in place" do
      owner_guid = stationary_owner(orientation: :math.pi())
      state = pet_beside_owner(owner_guid)

      context = AIEnvironment.context(state, @now)

      assert {{:running, _delay}, turned, %Blackboard{}} = PetBT.follow_owner(state, %Blackboard{}, context)
      assert turned.movement_block.position == state.movement_block.position
      assert turned.internal.events == []
    end

    test "despawns when the owner is gone" do
      owner_guid = Guid.from_low_guid(:player, :erlang.unique_integer([:positive]))
      state = pet_beside_owner(owner_guid)

      context = AIEnvironment.context(state, @now)

      assert {:success, despawned, %Blackboard{}} = PetBT.follow_owner(state, %Blackboard{}, context)
      assert [%Effects.DespawnSelf{}] = despawned.internal.events
    end
  end

  describe "command/3" do
    test "stay stops the active spline through the movement transition" do
      state = active_pet()

      stopped = PetBT.command(state, :stay, 0)

      assert stopped.movement_block.spline_nodes == []
      assert Enum.any?(stopped.internal.events, &is_struct(&1, Effects.MovementStopped))
    end
  end

  describe "reaction/2" do
    test "passive stops the active spline through the movement transition" do
      state = active_pet()

      stopped = PetBT.reaction(state, :passive)

      assert stopped.movement_block.spline_nodes == []
      assert Enum.any?(stopped.internal.events, &is_struct(&1, Effects.MovementStopped))
    end
  end

  defp stationary_owner(opts) do
    guid = Guid.from_low_guid(:player, :erlang.unique_integer([:positive]))
    SpatialHash.update(:players, guid, world(), 0.0, 0.0, 0.0)

    Metadata.put(guid, %{
      orientation: Keyword.fetch!(opts, :orientation),
      bounding_radius: Unit.default_bounding_radius()
    })

    on_exit(fn ->
      SpatialHash.remove(:players, guid)
      Metadata.delete(guid)
    end)

    guid
  end

  defp pet_beside_owner(owner_guid) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:pet, 1, :erlang.unique_integer([:positive]))},
      unit: %Unit{bounding_radius: Unit.default_bounding_radius()},
      internal: %Internal{
        world: world(),
        pet: %Internal.Pet{owner_guid: owner_guid, command_state: :follow}
      },
      movement_block: %MovementBlock{position: {0.0, 2.0, 0.0, 0.0}, run_speed: 7.0}
    }
  end

  defp active_pet do
    owner_guid = Guid.from_low_guid(:player, :erlang.unique_integer([:positive]))
    state = pet_beside_owner(owner_guid)

    %{
      state
      | internal: %{
          state.internal
          | movement_start_time: @now,
            movement_start_position: {0.0, 2.0, 0.0}
        },
        movement_block: %{
          state.movement_block
          | spline_nodes: [{10.0, 2.0, 0.0}],
            duration: 1_000
        }
    }
  end

  defp world, do: %WorldRef{map_id: 0}
end
