defmodule ThistleTea.Game.Core.AI.CreatureScript.BartlebyTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @bartleby 6_090
  @beat_bartleby 1_640
  @enemy 168

  setup do
    %{bartleby: bartleby(), player: Guid.from_low_guid(:player, Unique.integer())}
  end

  describe "quest_start_steps/0" do
    test "accepting Beat Bartleby turns him on the player" do
      assert [%ScriptStep{command: :set_faction, datalong: @enemy}, %ScriptStep{command: :attack_start}] =
               Map.fetch!(CreatureScript.quest_start_steps(), @beat_bartleby)
    end
  end

  describe "events/1" do
    test "he arrives unable to fall below fifteen percent", %{bartleby: bartleby} do
      {bartleby, _blackboard} = EventAI.on_spawned(bartleby, Blackboard.new(), 0, Context.new(0))

      assert bartleby.internal.invincibility_health_threshold == 150
    end

    test "at fifteen percent he yields once to the player he is fighting", %{bartleby: bartleby, player: player} do
      [_spawned, yield, _leave_combat] = CreatureScript.events(@bartleby)
      assert %{event_type: :hp, param1: 15, param2: 0, repeatable?: false} = yield

      {bartleby, _blackboard} =
        Script.run(bartleby, Blackboard.new(), List.flatten(yield.actions), player, Context.new(0))

      assert [
               %Effects.QuestEventCredit{player_guid: ^player, quest_id: @beat_bartleby},
               %Effects.EnterEvade{}
             ] =
               Enum.filter(bartleby.internal.events, &(&1.__struct__ in [Effects.QuestEventCredit, Effects.EnterEvade]))
    end
  end

  defp bartleby do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, @bartleby, Unique.integer()), entry: @bartleby},
      unit: %Unit{health: 1_000, max_health: 1_000, level: 10, auras: [], flags: 0, faction_template: 12},
      movement_block: %MovementBlock{position: {-8_000.0, 500.0, 96.0, 0.0}},
      internal: %Internal{
        world: %WorldRef{map_id: 0},
        name: "Bartleby",
        creature: %Creature{ai_events: CreatureScript.events(@bartleby)}
      }
    }
  end
end
