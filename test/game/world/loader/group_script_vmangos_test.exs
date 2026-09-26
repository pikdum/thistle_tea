defmodule ThistleTea.Game.World.Loader.GroupScriptVmangosTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.World.Loader.Script

  @moduletag :vmangos_db

  describe "load_by_ids/2" do
    test "resolves the Stratholme patrol's shared home-position script" do
      scripts = Script.load_by_ids(Mangos.CreatureMovementScript, [52_124])
      step = Enum.find(scripts[52_124], &(&1.command == :start_script_on_group))
      assert ScriptStep.start_script_options(step) == [{5, 100}]
      assert [%ScriptStep{command: :set_home_position, datalong: 1}] = step.sub_scripts[5]
    end
  end
end
