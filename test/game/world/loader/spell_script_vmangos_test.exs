defmodule ThistleTea.Game.World.Loader.SpellScriptVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.World.Loader.SpellScript

  @moduletag :vmangos_db

  setup do
    SpellScript.init()
    SpellScript.load_all()
    :ok
  end

  describe "get/1" do
    test "loads Soul Link's VMangos cast command and target swap" do
      assert [
               %ScriptStep{
                 command: :cast_spell,
                 datalong: 18_814,
                 target_type: :provided,
                 swap_initial?: true
               }
             ] = SpellScript.get(19_028)
    end
  end
end
