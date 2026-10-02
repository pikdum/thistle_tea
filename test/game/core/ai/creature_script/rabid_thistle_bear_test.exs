defmodule ThistleTea.Game.Core.AI.CreatureScript.RabidThistleBearTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Blackboard.Follow
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventAI
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

  @rabid_thistle_bear 2_164
  @captured_bear 11_836
  @bear_captured_in_trap 9_439

  setup [:bear]

  describe "CreatureScript" do
    test "replaces the rabid bear's AI with the port" do
      assert CreatureScript.ported?(@rabid_thistle_bear)
      assert @captured_bear in CreatureScript.creature_entries()
    end
  end

  describe "events/1" do
    test "a trapped bear is captured for the trapper once", %{bear: bear, trapper: trapper} do
      {bear, blackboard} = EventAI.on_spell_hit(bear, Blackboard.new(), trapper, 1, 0, Context.new(0))
      assert bear.internal.events == []

      {bear, blackboard} = EventAI.on_spell_hit(bear, blackboard, trapper, @bear_captured_in_trap, 0, Context.new(0))

      assert %Follow{guid: ^trapper, distance: 2.0} = blackboard.navigation.follow

      assert [
               %Effects.QuestKillCredit{player_guid: ^trapper, creature_entry: @captured_bear},
               %Effects.EnterEvade{},
               %Effects.DespawnSelf{duration_ms: 300_000}
             ] = bear.internal.events

      bear = %{bear | internal: %{bear.internal | events: []}}

      {bear, _blackboard} =
        EventAI.on_spell_hit(bear, blackboard, trapper, @bear_captured_in_trap, 100, Context.new(100))

      refute Enum.any?(bear.internal.events, &match?(%Effects.QuestKillCredit{}, &1))
    end

    test "the captured bear takes its friendly entry" do
      [%{actions: [steps]}] = CreatureScript.events(@rabid_thistle_bear)
      assert %ScriptStep{datalong: @captured_bear} = Enum.find(steps, &(&1.command == :update_entry))
    end
  end

  defp bear(_context) do
    guid = Guid.from_low_guid(:mob, @rabid_thistle_bear, Unique.integer())

    bear = %Mob{
      object: %Object{guid: guid, entry: @rabid_thistle_bear},
      unit: %Unit{health: 300, max_health: 300, level: 13, auras: [], flags: 0, faction_template: 44},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: %WorldRef{map_id: 1},
        name: "Rabid Thistle Bear",
        creature: %Creature{ai_events: CreatureScript.events(@rabid_thistle_bear)}
      }
    }

    %{bear: bear, trapper: Guid.from_low_guid(:player, Unique.integer())}
  end
end
