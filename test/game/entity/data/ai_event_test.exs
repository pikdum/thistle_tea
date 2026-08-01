defmodule ThistleTea.Game.Entity.Data.AIEventTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.AIEvent
  alias ThistleTea.Game.Entity.Data.ScriptStep

  describe "build/2" do
    test "decodes event types, flags, and resolves action scripts" do
      step = %ScriptStep{script_id: 58_900, command: :cast_spell, datalong: 12_544}

      event =
        AIEvent.build(
          %{
            id: 58_900,
            event_type: 1,
            event_inverse_phase_mask: 0,
            event_chance: 100,
            event_flags: 1,
            event_param1: 1_000,
            event_param2: 1_000,
            event_param3: 1_800_000,
            event_param4: 1_800_000,
            action1_script: 58_900,
            action2_script: 0,
            action3_script: 0,
            condition_id: 0
          },
          %{58_900 => [step]}
        )

      assert event.event_type == :timer_ooc
      assert event.repeatable?
      refute event.random_action?
      assert event.param1 == 1_000
      assert event.actions == [[step]]
      assert AIEvent.timed?(event)
    end

    test "drops actions whose scripts are missing" do
      event =
        AIEvent.build(
          %{
            id: 1,
            event_type: 4,
            event_inverse_phase_mask: 0,
            event_chance: 100,
            event_flags: 0,
            event_param1: 0,
            event_param2: 0,
            event_param3: 0,
            event_param4: 0,
            action1_script: 999,
            action2_script: 0,
            action3_script: 0,
            condition_id: 0
          },
          %{}
        )

      assert event.event_type == :aggro
      assert event.actions == []
      refute AIEvent.timed?(event)
    end

    test "decodes scripted event notifications" do
      row = %{
        id: 1,
        event_type: 31,
        event_inverse_phase_mask: 0,
        event_chance: 100,
        event_flags: 0,
        event_param1: 5862,
        event_param2: 7,
        event_param3: 0,
        event_param4: 0,
        action1_script: 0,
        action2_script: 0,
        action3_script: 0,
        condition_id: 0
      }

      assert %AIEvent{event_type: :script_event, param1: 5862, param2: 7} = AIEvent.build(row, %{})
    end

    test "decodes aura, emote, line-of-sight, and rooted event families" do
      base = %{
        id: 1,
        event_inverse_phase_mask: 0,
        event_chance: 100,
        event_flags: 0,
        event_param1: 0,
        event_param2: 0,
        event_param3: 0,
        event_param4: 0,
        action1_script: 0,
        action2_script: 0,
        action3_script: 0,
        condition_id: 0
      }

      expected = %{
        10 => :ooc_los,
        15 => :friendly_is_cc,
        16 => :friendly_missing_buff,
        18 => :target_mana,
        22 => :receive_emote,
        23 => :aura,
        24 => :target_aura,
        27 => :missing_aura,
        28 => :target_missing_aura,
        33 => :victim_rooted,
        36 => :spell_hit_target
      }

      assert Map.new(expected, fn {id, _type} -> {id, AIEvent.build(Map.put(base, :event_type, id), %{}).event_type} end) ==
               expected
    end
  end

  describe "phase_allows?/2" do
    test "blocks events whose inverse phase mask covers the current phase" do
      event = %AIEvent{inverse_phase_mask: 0b0010}

      assert AIEvent.phase_allows?(event, 0)
      refute AIEvent.phase_allows?(event, 1)
      assert AIEvent.phase_allows?(event, 2)
    end
  end
end
