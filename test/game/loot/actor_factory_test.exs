defmodule ThistleTea.Game.Loot.ActorFactoryTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Condition, as: Evaluator
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Loot.ActorFactory
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  describe "for_character/2 and for_guid/2" do
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

      assert Evaluator.evaluate(actor.condition_context, %Condition{type: :item, value1: 100, value2: 3}) == :met

      assert Evaluator.evaluate(actor.condition_context, %Condition{type: :quest_rewarded, value1: 200}) == :met
    end

    test "loot sources use the owner's authoritative spawn DB guid" do
      player_guid = Guid.from_low_guid(:player, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      condition = %Condition{type: :db_guid, value1: 123}

      Metadata.put(target_guid, %{db_guid: 123})
      on_exit(fn -> Metadata.delete(target_guid) end)

      actor = ActorFactory.for_guid(player_guid, target_guid)
      assert Evaluator.evaluate(actor.condition_context, condition) == :met

      Metadata.update(target_guid, %{db_guid: nil})
      actor = ActorFactory.for_guid(player_guid, target_guid)
      assert {:unknown, _reasons} = Evaluator.evaluate(actor.condition_context, condition)
    end
  end

  defp unique_guid, do: System.unique_integer([:positive, :monotonic])
end
