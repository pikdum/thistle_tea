defmodule ThistleTea.Game.Entity.Logic.AI.ScriptTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Guid

  setup [:mob]

  describe "run/5" do
    test "talk enqueues a monster talk event plus the text emote", %{mob: mob} do
      step = %ScriptStep{
        command: :talk,
        texts: [%{text: "Hello there!", chat_type: :say, language: 0, emote_id: 5}]
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [
               %Event{type: :monster_talk, text: "Hello there!", chat_type: :say},
               %Event{type: :emote, emote_id: 5}
             ] = mob.internal.events
    end

    test "emote enqueues an emote event", %{mob: mob} do
      step = %ScriptStep{command: :emote, datalong: 11}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Event{type: :emote, emote_id: 11}] = mob.internal.events
    end

    test "triggered self cast enqueues a trigger spell event", %{mob: mob} do
      step = %ScriptStep{command: :cast_spell, datalong: 12_544, datalong2: 0x02, target_self?: true}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      guid = mob.object.guid

      assert [%Event{type: :trigger_spell, spell_id: 12_544, source_guid: ^guid, target_guid: ^guid}] =
               mob.internal.events
    end

    test "non-triggered casts use the real cast path, not the trigger pipeline", %{mob: mob} do
      # castflags 0x01 = interrupt_previous only (not triggered) → visible cast via
      # the mob casting machinery. With an empty fixture spellbook it finds no spell
      # and no-ops, but it must never fall back to the instant trigger pipeline.
      step = %ScriptStep{command: :cast_spell, datalong: 12_544, datalong2: 0x01, target_self?: true}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      refute Enum.any?(mob.internal.events, &(&1.type == :trigger_spell))
    end

    test "cast without a resolvable target is skipped", %{mob: mob} do
      step = %ScriptStep{command: :cast_spell, datalong: 12_544, target_type: :victim}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.internal.events == []
    end

    test "set_phase variants mutate the blackboard phase", %{mob: mob} do
      blackboard = Blackboard.new()

      {_mob, blackboard} = Script.run(mob, blackboard, [%ScriptStep{command: :set_phase, datalong: 3}], nil, 0)
      assert blackboard.eventai_phase == 3

      {_mob, blackboard} =
        Script.run(mob, blackboard, [%ScriptStep{command: :set_phase, datalong: 2, datalong2: 1}], nil, 0)

      assert blackboard.eventai_phase == 5

      {_mob, blackboard} =
        Script.run(mob, blackboard, [%ScriptStep{command: :set_phase, datalong: 9, datalong2: 2}], nil, 0)

      assert blackboard.eventai_phase == 0

      {_mob, blackboard} =
        Script.run(mob, blackboard, [%ScriptStep{command: :set_phase_range, datalong: 4, datalong2: 4}], nil, 0)

      assert blackboard.eventai_phase == 4

      {_mob, blackboard} =
        Script.run(mob, blackboard, [%ScriptStep{command: :set_phase_random, datalong: 7, datalong2: 7}], nil, 0)

      assert blackboard.eventai_phase == 7
    end

    test "flee marks the blackboard and emotes when a victim exists", %{mob: mob} do
      victim = Guid.from_low_guid(:player, 7)
      mob = %{mob | unit: %{mob.unit | target: victim}}

      {mob, blackboard} = Script.run(mob, Blackboard.new(), [%ScriptStep{command: :flee}], nil, 2_000)

      assert Blackboard.fleeing?(blackboard)
      assert blackboard.flee_until == 2_000 + Script.flee_duration_ms()
      assert blackboard.flee_from == victim
      assert [%Event{type: :monster_talk, chat_type: :text_emote}] = mob.internal.events
    end

    test "flee without a victim is ignored", %{mob: mob} do
      {mob, blackboard} = Script.run(mob, Blackboard.new(), [%ScriptStep{command: :flee}], nil, 2_000)

      refute Blackboard.fleeing?(blackboard)
      assert mob.internal.events == []
    end

    test "morph to a display id swaps the model and marks a broadcast", %{mob: mob} do
      step = %ScriptStep{command: :morph, datalong: 89, datalong2: 1}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.unit.display_id == 89
      assert mob.internal.broadcast_update?
    end

    test "morph to zero restores the native display id", %{mob: mob} do
      mob = %{mob | unit: %{mob.unit | display_id: 89}}
      step = %ScriptStep{command: :morph, datalong: 0}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.unit.display_id == 11_354
      assert mob.internal.broadcast_update?
    end

    test "morph to the current display id is a no-op", %{mob: mob} do
      step = %ScriptStep{command: :morph, datalong: 11_354, datalong2: 1}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.unit.display_id == 11_354
      refute mob.internal.broadcast_update?
    end

    test "morph by creature entry is skipped", %{mob: mob} do
      step = %ScriptStep{command: :morph, datalong: 6_578, datalong2: 0}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.unit.display_id == 11_354
      refute mob.internal.broadcast_update?
    end

    test "morph is skipped while dead", %{mob: mob} do
      mob = %{mob | unit: %{mob.unit | health: 0}}
      step = %ScriptStep{command: :morph, datalong: 89, datalong2: 1}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.unit.display_id == 11_354
      refute mob.internal.broadcast_update?
    end

    test "set_run flips the running flag and persists run mode on the blackboard", %{mob: mob} do
      {mob, blackboard} =
        Script.run(mob, Blackboard.new(), [%ScriptStep{command: :set_run, datalong: 1}], nil, 1_000)

      assert mob.internal.running
      assert Blackboard.run_mode?(blackboard)

      {mob, blackboard} = Script.run(mob, blackboard, [%ScriptStep{command: :set_run, datalong: 0}], nil, 1_000)

      refute mob.internal.running
      refute Blackboard.run_mode?(blackboard)
    end

    test "steps with a failing condition are skipped", %{mob: mob} do
      failing = %Condition{type: :db_guid, value1: 12_345}

      step = %ScriptStep{command: :emote, datalong: 11, condition: failing}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.internal.events == []
    end

    test "delayed steps are deferred through a script_steps event", %{mob: mob} do
      immediate = %ScriptStep{command: :emote, datalong: 11}
      delayed = %ScriptStep{command: :emote, datalong: 22, delay_ms: 4_000}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [immediate, delayed], nil, 1_000)

      assert [
               %Event{type: :emote, emote_id: 11},
               %Event{type: :script_steps, steps: [^delayed], duration_ms: 4_000}
             ] = mob.internal.events
    end

    test "unsupported commands are skipped", %{mob: mob} do
      step = %ScriptStep{command: {:unsupported, 10}}

      {mob, blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.internal.events == []
      assert blackboard == Blackboard.new()
    end
  end

  defp mob(_context) do
    mob = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 589, 1)},
      unit: %Unit{
        health: 100,
        max_health: 100,
        level: 14,
        target: 0,
        auras: [],
        display_id: 11_354,
        native_display_id: 11_354
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        map: 0,
        name: "Defias Pillager",
        in_combat: false,
        creature: %Creature{},
        spellbook: %{}
      }
    }

    {:ok, mob: mob}
  end
end
