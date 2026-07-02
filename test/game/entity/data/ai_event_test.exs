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
