defmodule ThistleTea.Game.Core.AI.CreatureScript.LazyPeonTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.LazyPeon
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @peon 10_556
  @sleep 17_743
  @awaken 19_938

  setup [:peon]

  describe "CreatureScript" do
    test "replaces the lazy peon's EventAI with its port" do
      assert CreatureScript.ported?(@peon)
      refute CreatureScript.ported?(1)
      assert @peon in CreatureScript.entries()
      assert CreatureScript.events(1) == []
      assert Enum.map(CreatureScript.events(@peon), & &1.id) == [1_055_601, 1_055_602, 1_055_603, 1_055_604]
    end
  end

  describe "events/1" do
    test "falls back asleep whenever the sleep aura lapses", %{peon: peon} do
      {lapsed, _blackboard} = EventAI.tick(peon, Blackboard.new(), 0, Context.new(0))
      assert Enum.any?(lapsed.internal.events, &match?(%Effects.SpellStart{spell_id: @sleep}, &1))

      asleep = %{peon | unit: %{peon.unit | auras: [%Holder{spell: peon.internal.spellbook[@sleep], auras: []}]}}
      {asleep, _blackboard} = EventAI.tick(asleep, Blackboard.new(), 0, Context.new(0))
      refute Enum.any?(asleep.internal.events, &match?(%Effects.SpellStart{}, &1))

      {working, _blackboard} = EventAI.tick(peon, put_phase(Blackboard.new(), 2), 0, Context.new(0))
      refute Enum.any?(working.internal.events, &match?(%Effects.SpellStart{}, &1))
    end

    test "credits the player once per nap and sends the peon to work", %{peon: peon, player: player} do
      {peon, blackboard} = EventAI.on_spell_hit(peon, Blackboard.new(), player, 1, 0, Context.new(0))
      assert peon.internal.events == []

      {peon, blackboard} = EventAI.on_spell_hit(peon, blackboard, player, @awaken, 0, Context.new(0))

      assert [
               %Effects.QuestKillCredit{player_guid: ^player, creature_entry: @peon, group?: false},
               %Effects.ScriptSteps{
                 duration_ms: 3_000,
                 steps: [%ScriptStep{command: :remove_aura, datalong: @sleep} | _]
               }
             ] = peon.internal.events

      assert blackboard.event_ai.phase == 1
      assert map_size(peon.internal.scripts.runs) == 1

      peon = %{peon | internal: %{peon.internal | events: []}}
      {peon, _blackboard} = EventAI.on_spell_hit(peon, blackboard, player, @awaken, 1_000, Context.new(1_000))
      assert peon.internal.events == []
    end

    test "chops wood on reaching the pile and sleeps again at home", %{peon: peon} do
      blackboard = put_phase(Blackboard.new(), 1)
      {peon, blackboard} = EventAI.on_movement_inform(peon, blackboard, 9, 1, Context.new(0))
      assert %Effects.Emote{emote_id: 234} in peon.internal.events
      assert blackboard.event_ai.phase == 2

      {peon, blackboard} = EventAI.on_reached_home(peon, blackboard, 1_000)
      assert Enum.any?(peon.internal.events, &match?(%Effects.SpellStart{spell_id: @sleep}, &1))
      assert blackboard.event_ai.phase == 0
    end

    test "walks to the nearest lumber pile after waking" do
      [_spawned, %{actions: [steps]} | _rest] = LazyPeon.events(@peon)

      %ScriptStep{datalong: script_id, dataint: 100, sub_scripts: scripts} =
        Enum.find(steps, &(&1.command == :start_script))

      steps = Map.fetch!(scripts, script_id)
      move = Enum.find(steps, &(&1.command == :move_to))

      assert %ScriptStep{
               target_type: :nearest_game_object_with_entry,
               target_param1: 175_784,
               target_param2: 20,
               datalong: 2,
               datalong4: 2,
               dataint: 1,
               delay_ms: 5_000
             } = move

      assert %ScriptStep{dataint: 5_774, delay_ms: 5_000} = Enum.find(steps, &(&1.command == :talk))
    end
  end

  defp put_phase(blackboard, phase), do: %{blackboard | event_ai: %{blackboard.event_ai | phase: phase}}

  defp peon(_context) do
    sleep = %Spell{
      id: @sleep,
      name: "Lazy Peon Sleep",
      school: :physical,
      cast_time_ms: 0,
      range_yards: 0.0,
      mana_cost: 0,
      power_type: 0,
      attributes: MapSet.new(),
      effects: []
    }

    peon = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, @peon, Unique.integer()), entry: @peon},
      unit: %Unit{health: 100, max_health: 100, level: 4, auras: [], flags: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: %WorldRef{map_id: 1},
        name: "Lazy Peon",
        creature: %Creature{ai_events: CreatureScript.events(@peon)},
        spellbook: %{@sleep => sleep}
      }
    }

    %{peon: peon, player: Guid.from_low_guid(:player, Unique.integer())}
  end
end
