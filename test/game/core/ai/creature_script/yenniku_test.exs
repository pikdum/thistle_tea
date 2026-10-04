defmodule ThistleTea.Game.Core.AI.CreatureScript.YennikuTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition
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

  @yenniku 2_530
  @yenniku_release 3_607
  @bloodscalp 28
  @horde_generic 83
  @on_the_quest %Condition{type: :quest_taken, value1: 592, value2: 1}

  setup do
    player = Guid.from_low_guid(:player, Unique.integer())
    %{player: player, yenniku: yenniku(player)}
  end

  describe "events/1" do
    test "the Soul Gem stuns him and turns him friendly", %{yenniku: yenniku, player: player} do
      {yenniku, blackboard} = release(yenniku, Blackboard.new(), player, :met)

      assert blackboard.event_ai.phase == 1
      assert yenniku.unit.faction_template == @horde_generic
      refute yenniku.internal.in_combat
      assert yenniku.internal.threat == %{}
      assert %Effects.Emote{emote_id: 64} in yenniku.internal.events

      assert %Effects.ScriptSteps{duration_ms: 60_000, steps: steps} =
               Enum.find(yenniku.internal.events, &match?(%Effects.ScriptSteps{}, &1))

      assert [
               %ScriptStep{command: :set_faction, datalong: 0},
               %ScriptStep{command: :enter_evade},
               %ScriptStep{command: :set_phase, datalong: 0}
             ] = steps
    end

    test "the gem does nothing to him for a player off the quest", %{yenniku: yenniku, player: player} do
      {yenniku, blackboard} = release(yenniku, Blackboard.new(), player, :unmet)

      assert blackboard.event_ai.phase == 0
      assert yenniku.unit.faction_template == @bloodscalp
      assert yenniku.internal.in_combat
    end

    test "a second gem while he is stunned changes nothing", %{yenniku: yenniku, player: player} do
      {yenniku, blackboard} = release(yenniku, Blackboard.new(), player, :met)
      yenniku = %{yenniku | internal: %{yenniku.internal | events: []}}

      {yenniku, _blackboard} = release(yenniku, blackboard, player, :met)
      assert yenniku.internal.events == []
    end

    test "he stops looking stunned when he evades" do
      assert [%{actions: [[%ScriptStep{command: :emote, datalong: 0}]]}] =
               Enum.filter(CreatureScript.events(@yenniku), &(&1.event_type == :evade))
    end
  end

  defp release(yenniku, blackboard, player, quest) do
    context = Context.new(1_000, script_conditions: %{@on_the_quest => quest})
    EventAI.on_spell_hit(yenniku, blackboard, player, @yenniku_release, 1_000, context)
  end

  defp yenniku(player) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, @yenniku, Unique.integer()), entry: @yenniku},
      unit: %Unit{
        health: 100,
        max_health: 100,
        level: 41,
        auras: [],
        flags: 0,
        npc_flags: 0x2,
        faction_template: @bloodscalp,
        target: player
      },
      movement_block: %MovementBlock{position: {-11_400.0, 1_960.0, 10.0, 0.0}},
      internal: %Internal{
        world: WorldRef.open(0),
        name: "Yenniku",
        in_combat: true,
        threat: %{player => 100},
        creature: %Creature{ai_events: CreatureScript.events(@yenniku)}
      }
    }
  end
end
