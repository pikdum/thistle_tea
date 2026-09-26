defmodule ThistleTea.Game.World.Loader.GuardianScriptVmangosTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.World.Loader.Script

  @moduletag :vmangos_db

  describe "load_by_ids/2" do
    test "decodes Ilkrud's guardian cleanup on evade" do
      scripts = Script.load_by_ids(Mangos.CreatureAiScript, [366_401])
      assert [%ScriptStep{command: :remove_guardians, datalong: 0}] = scripts[366_401]
    end
  end
end
