defmodule ThistleTea.Game.Entity.Data.ScriptStepTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.ScriptStep

  describe "build/1" do
    test "decodes commands, delays, and target flags" do
      step =
        ScriptStep.build(%{
          id: 100,
          delay: 3,
          priority: 1,
          command: 15,
          datalong: 12_544,
          datalong2: 2,
          datalong3: 0,
          datalong4: 0,
          dataint: 0,
          dataint2: 0,
          dataint3: 0,
          dataint4: 0,
          target_type: 0,
          target_param1: 0,
          target_param2: 0,
          data_flags: 0x04,
          x: 1.0,
          y: 2.0,
          z: 3.0,
          o: 4.0,
          condition_id: 0
        })

      assert step.command == :cast_spell
      assert step.delay_ms == 3_000
      assert step.target_type == :provided
      assert step.target_self?
      refute step.swap_targets?
      assert step.position == {1.0, 2.0, 3.0, 4.0}
      assert ScriptStep.cast_spell_id(step) == 12_544
    end

    test "keeps unsupported commands and target types as tagged ids" do
      step =
        ScriptStep.build(%{
          id: 5,
          delay: 0,
          priority: 0,
          command: 30,
          datalong: 0,
          datalong2: 0,
          datalong3: 0,
          datalong4: 0,
          dataint: 0,
          dataint2: 0,
          dataint3: 0,
          dataint4: 0,
          target_type: 25,
          target_param1: 0,
          target_param2: 0,
          data_flags: 0,
          x: 0.0,
          y: 0.0,
          z: 0.0,
          o: 0.0,
          condition_id: 0
        })

      assert step.command == {:unsupported, 30}
      assert step.target_type == {:unsupported, 25}
    end
  end

  describe "talk_text_ids/1" do
    test "collects the non-zero broadcast text ids of talk steps" do
      step = %ScriptStep{command: :talk, dataint: 1_866, dataint2: 1_867, dataint3: 0, dataint4: 0}

      assert ScriptStep.talk_text_ids(step) == [1_866, 1_867]
      assert ScriptStep.talk_text_ids(%ScriptStep{command: :emote, dataint: 5}) == []
    end
  end

  describe "emote_ids/1" do
    test "collects the non-zero emote ids of emote steps" do
      step = %ScriptStep{command: :emote, datalong: 11, datalong2: 0}

      assert ScriptStep.emote_ids(step) == [11]
      assert ScriptStep.emote_ids(%ScriptStep{command: :talk, datalong: 11}) == []
    end
  end
end
