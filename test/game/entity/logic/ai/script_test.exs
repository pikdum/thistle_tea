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

    test "summon_creature enqueues a summon event with explicit coordinates", %{mob: mob} do
      step = %ScriptStep{
        command: :summon_creature,
        datalong: 1_500,
        datalong2: 30_000,
        dataint: 0x01,
        dataint3: -1,
        dataint4: 3,
        position: {10.0, 20.0, 30.0, 1.5}
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Event{type: :summon_creature, summon: summon, steps: []}] = mob.internal.events
      assert summon.entry == 1_500
      assert summon.despawn_delay_ms == 30_000
      assert summon.despawn_type == 3
      assert summon.run?
      refute summon.unique?
      assert summon.position == {10.0, 20.0, 30.0, 1.5}
      assert summon.attack_guid == nil
    end

    test "summon_creature falls back to the summoner position and resolves the attack target", %{mob: mob} do
      victim = Guid.from_low_guid(:player, 9)

      mob = %{
        mob
        | unit: %{mob.unit | target: victim},
          movement_block: %{mob.movement_block | position: {5.0, 6.0, 7.0, 0.5}}
      }

      sub_steps = [%ScriptStep{command: :emote, datalong: 11}]

      step = %ScriptStep{
        command: :summon_creature,
        datalong: 1_500,
        dataint2: 777,
        dataint3: 1,
        position: {0.0, 0.0, 0.0, 0.0},
        sub_scripts: %{777 => sub_steps}
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Event{type: :summon_creature, summon: summon, steps: ^sub_steps}] = mob.internal.events
      assert summon.position == {5.0, 6.0, 7.0, 0.5}
      assert summon.attack_guid == victim
    end

    test "despawn enqueues a despawn_self event with seconds-scaled respawn delay", %{mob: mob} do
      step = %ScriptStep{command: :despawn, datalong: 2_000, datalong2: 30}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Event{type: :despawn_self, duration_ms: 2_000, respawn_delay_ms: 30_000}] = mob.internal.events
    end

    test "attack_start targets the victim and skips without one", %{mob: mob} do
      step = %ScriptStep{command: :attack_start, target_type: :victim}

      {idle, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)
      assert idle.internal.events == []

      victim = Guid.from_low_guid(:player, 9)
      mob = %{mob | unit: %{mob.unit | target: victim}}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)
      assert [%Event{type: :attack_start, target_guid: ^victim}] = mob.internal.events
    end

    test "start_script runs the chosen resolved sub-script", %{mob: mob} do
      sub_steps = [%ScriptStep{command: :emote, datalong: 11}]

      step = %ScriptStep{
        command: :start_script,
        datalong: 555,
        dataint: 100,
        sub_scripts: %{555 => sub_steps}
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Event{type: :emote, emote_id: 11}] = mob.internal.events
    end

    test "stand_state updates the unit and marks a broadcast", %{mob: mob} do
      step = %ScriptStep{command: :stand_state, datalong: 1}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.unit.stand_state == 1
      assert mob.internal.broadcast_update?
    end

    test "mount sets and clears the mount display id", %{mob: mob} do
      step = %ScriptStep{command: :mount, datalong: 2_404, datalong2: 1}

      {mob, blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)
      assert mob.unit.mount_display_id == 2_404

      {mob, _blackboard} = Script.run(mob, blackboard, [%ScriptStep{command: :mount, datalong: 0}], nil, 1_000)
      assert mob.unit.mount_display_id == 0
    end

    test "mount by unresolved creature entry is skipped", %{mob: mob} do
      step = %ScriptStep{command: :mount, datalong: 14, datalong2: 0}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.unit.mount_display_id == nil
      refute mob.internal.broadcast_update?
    end

    test "turn_to an orientation faces in place and enqueues a facing event", %{mob: mob} do
      step = %ScriptStep{command: :turn_to, datalong: 1, position: {0.0, 0.0, 0.0, 2.5}}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert {_x, _y, _z, 2.5} = mob.movement_block.position
      assert [%Event{type: :set_facing, facing: {:angle, 2.5}}] = mob.internal.events
    end

    test "turn_to the victim enqueues a facing-target event", %{mob: mob} do
      victim = Guid.from_low_guid(:player, 9)
      mob = %{mob | unit: %{mob.unit | target: victim}}

      step = %ScriptStep{command: :turn_to, datalong: 0, target_type: :victim}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Event{type: :set_facing, facing: {:target, ^victim}}] = mob.internal.events
    end

    test "play_sound picks the object-sound variant for distance-dependent flags", %{mob: mob} do
      steps = [
        %ScriptStep{command: :play_sound, datalong: 6_943},
        %ScriptStep{command: :play_sound, datalong: 6_944, datalong2: 0x2}
      ]

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), steps, nil, 1_000)

      assert [
               %Event{type: :play_sound, sound_id: 6_943},
               %Event{type: :play_object_sound, sound_id: 6_944}
             ] = mob.internal.events
    end

    test "swap-final steps are forwarded to the resolved buddy", %{mob: mob} do
      buddy = Guid.from_low_guid(:mob, 10_616, 81_251)

      step = %ScriptStep{
        command: :talk,
        target_type: :creature_with_guid,
        target_param1: 81_251,
        buddy_guid: buddy,
        swap_final?: true,
        texts: [%{text: "Back to work!", chat_type: :say, language: 0, emote_id: 0}]
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      self_guid = mob.object.guid

      assert [
               %Event{
                 type: :forward_script_steps,
                 target_guid: ^buddy,
                 source_guid: ^self_guid,
                 steps: [forwarded]
               }
             ] = mob.internal.events

      assert forwarded.command == :talk
      assert forwarded.target_type == :provided
      refute forwarded.swap_final?
    end

    test "swap-final steps with an unresolved buddy are skipped", %{mob: mob} do
      step = %ScriptStep{
        command: :talk,
        target_type: :creature_with_guid,
        target_param1: 81_251,
        swap_final?: true,
        texts: [%{text: "Back to work!", chat_type: :say, language: 0, emote_id: 0}]
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.internal.events == []
    end

    test "swap-final steps resolving to self execute locally", %{mob: mob} do
      step = %ScriptStep{
        command: :emote,
        datalong: 11,
        target_type: :creature_with_guid,
        buddy_guid: mob.object.guid,
        swap_final?: true
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Event{type: :emote, emote_id: 11}] = mob.internal.events
    end

    test "swap-initial steps are skipped", %{mob: mob} do
      step = %ScriptStep{command: :emote, datalong: 11, swap_initial?: true}

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert mob.internal.events == []
    end

    test "turn_to faces a guid-selected buddy", %{mob: mob} do
      buddy = Guid.from_low_guid(:mob, 10_616, 81_251)

      step = %ScriptStep{
        command: :turn_to,
        datalong: 0,
        target_type: :creature_with_guid,
        buddy_guid: buddy
      }

      {mob, _blackboard} = Script.run(mob, Blackboard.new(), [step], nil, 1_000)

      assert [%Event{type: :set_facing, facing: {:target, ^buddy}}] = mob.internal.events
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
