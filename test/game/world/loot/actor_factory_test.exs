defmodule ThistleTea.Game.World.Loot.ActorFactoryTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Condition
  alias ThistleTea.Game.Core.Condition.Subject
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Item.ItemEligibility
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loot.ActorFactory
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.ServerVariables

  describe "for_character/2 and for_guid/2" do
    test "refresh global conditions for both local and remote loot actors" do
      guid = Guid.from_low_guid(:player, unique_guid())
      index = unique_guid()
      on_exit(fn -> :ets.delete(ServerVariables, index) end)

      character = %Character{
        object: %Object{guid: guid},
        player: %Player{},
        unit: %Unit{class: 1, race: 1, level: 20, health: 100, max_health: 100},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      condition = %Condition{type: :saved_variable, value1: index, value2: 0}
      local = ActorFactory.for_character(character, 0).condition_context
      remote = ActorFactory.for_guid(guid, 0).condition_context
      assert Condition.evaluate(local, condition) == :met
      assert Condition.evaluate(remote, condition) == :met
      ServerVariables.put(index, 1)
      assert Condition.evaluate(ActorFactory.for_character(character, 0).condition_context, condition) == :unmet
      assert Condition.evaluate(ActorFactory.for_guid(guid, 0).condition_context, condition) == :unmet
      assert Condition.evaluate(local, condition) == :met
    end

    test "refresh item eligibility through owner updates and reconnect" do
      player_guid = Guid.from_low_guid(:player, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())

      character = %Character{
        object: %Object{guid: player_guid},
        unit: %Unit{class: 1, race: 1, level: 20, health: 100, max_health: 100},
        player: %Player{skills: %{}},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      on_exit(fn -> Presence.leave(character) end)
      Presence.enter(character, %{})
      initial = ActorFactory.for_character(character, target_guid).item_eligibility
      assert %ItemEligibility{level: 20} = initial
      assert ActorFactory.for_guid(player_guid, target_guid).item_eligibility == initial

      updated = %{
        character
        | unit: %{character.unit | level: 30},
          player: %{character.player | skills: %{164 => %{value: 100}}, highest_honor_rank: 6},
          internal: %{character.internal | spells: [9788]}
      }

      Presence.sync(updated, %{item_eligibility: initial})
      local = ActorFactory.for_character(updated, target_guid).item_eligibility
      assert ActorFactory.for_guid(player_guid, target_guid).item_eligibility == local
      assert local.level == 30
      assert local.highest_honor_rank == 6
      assert local.proficiency.skill_values == %{164 => 100}
      assert MapSet.member?(local.proficiency.known_spell_ids, 9788)

      Presence.relocate(updated)
      assert ActorFactory.for_guid(player_guid, target_guid).item_eligibility == local
      Presence.sync(character, %{})
      assert ActorFactory.for_guid(player_guid, target_guid).item_eligibility == initial
      Presence.leave(character)
      assert ActorFactory.for_guid(player_guid, target_guid).item_eligibility == nil
      Presence.enter(updated, %{})
      assert ActorFactory.for_guid(player_guid, target_guid).item_eligibility == local
    end

    for entry <- 178_784..178_789 do
      test "deny supply #{entry} access without an active match reservation" do
        player_guid = Guid.from_low_guid(:player, unique_guid())
        target_guid = Guid.from_low_guid(:game_object, unquote(entry), unique_guid())
        world = WorldRef.instance(30, unique_guid())

        character = %Character{
          object: %Object{guid: player_guid},
          player: %Player{},
          movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
          internal: %Internal{world: world}
        }

        target = %GameObject{
          object: %Object{guid: target_guid},
          internal: %Internal{world: world},
          movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
        }

        on_exit(fn -> World.remove_position(target) end)
        World.update_position(target)
        refute ActorFactory.for_character(character, target_guid).access_allowed?
        refute ActorFactory.for_guid(player_guid, target_guid).access_allowed?
      end
    end

    test "use the same authoritative projected distance" do
      player_guid = Guid.from_low_guid(:player, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      world = WorldRef.open(0)
      now = Time.now()

      character = %Character{
        object: %Object{guid: player_guid},
        player: %Player{},
        internal: %Internal{world: world},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      target = %Mob{
        object: %Object{guid: target_guid},
        internal: %Internal{
          world: world,
          movement_start_time: now - 500,
          movement_start_position: {10.0, 0.0, 0.0}
        },
        movement_block: %MovementBlock{
          position: {10.0, 0.0, 0.0, 0.0},
          spline_nodes: [{0.0, 0.0, 0.0}],
          duration: 1_000
        }
      }

      on_exit(fn ->
        World.remove_position(character)
        World.remove_position(target)
      end)

      World.update_position(character)
      World.update_position(target)

      local = ActorFactory.for_character(character, target_guid)
      projected = ActorFactory.for_guid(player_guid, target_guid)

      assert_in_delta local.distance, projected.distance, 0.1
      assert local.distance < 7.0
    end

    test "remote actors retain player-owned condition facts" do
      player_guid = Guid.from_low_guid(:player, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())

      Metadata.put(player_guid, %{
        race: 1,
        class: 1,
        level: 20,
        alive?: true,
        condition_subject: %Subject{
          item_counts: %{100 => 3},
          rewarded_quests: MapSet.new([200]),
          quest_log: %{},
          reputation_ranks: %{}
        }
      })

      on_exit(fn -> Metadata.delete(player_guid) end)

      actor = ActorFactory.for_guid(player_guid, target_guid)

      assert Condition.evaluate(actor.condition_context, %Condition{type: :item, value1: 100, value2: 3}) == :met

      assert Condition.evaluate(actor.condition_context, %Condition{type: :quest_rewarded, value1: 200}) == :met
    end

    test "loot sources use the owner's authoritative spawn DB guid" do
      player_guid = Guid.from_low_guid(:player, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      condition = %Condition{type: :db_guid, value1: 123}

      Metadata.put(target_guid, %{db_guid: 123})
      on_exit(fn -> Metadata.delete(target_guid) end)

      actor = ActorFactory.for_guid(player_guid, target_guid)
      assert Condition.evaluate(actor.condition_context, condition) == :met

      Metadata.update(target_guid, %{db_guid: nil})
      actor = ActorFactory.for_guid(player_guid, target_guid)
      assert {:unknown, _reasons} = Condition.evaluate(actor.condition_context, condition)
    end
  end

  defp unique_guid, do: System.unique_integer([:positive, :monotonic])
end
