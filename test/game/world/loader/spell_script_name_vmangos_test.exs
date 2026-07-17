defmodule ThistleTea.Game.World.Loader.SpellScriptNameVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.SpellScriptName

  @moduletag :vmangos_db

  setup do
    SpellScriptName.init()
    SpellScriptName.load_all()
    :ok
  end

  describe "get/1" do
    test "loads the latest script label at or before the supported build" do
      assert SpellScriptName.get(2098) == "spell_rogue_eviscerate"
      assert SpellScriptName.get(23_989) == "spell_hunter_readiness"
      assert SpellScriptName.get(1122) == "spell_warlock_inferno"
      assert SpellScriptName.get(19_503) == nil
    end
  end
end
