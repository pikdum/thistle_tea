defmodule ThistleTea.Game.Core.AI.CreatureScript.ArchmageTervoshTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @tervosh 4967
  @missing_diplomat 1265

  describe "quest_end_steps/0" do
    test "turning in the report earns the Lady's blessing and Proudmoore's Defense" do
      assert [
               %ScriptStep{command: :talk, dataint: 1751},
               %ScriptStep{command: :cast_spell, datalong: 7120, datalong2: 0x02}
             ] = Map.fetch!(CreatureScript.quest_end_steps(), @missing_diplomat)
    end
  end

  describe "ported?/1" do
    test "leaves Tervosh's EventAI in place" do
      refute CreatureScript.ported?(@tervosh)
    end
  end
end
