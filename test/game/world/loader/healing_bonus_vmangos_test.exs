defmodule ThistleTea.Game.World.Loader.HealingBonusVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :vmangos_db

  describe "load_all/0" do
    test "loads receiving-heal coefficients and the Flash of Light wrapper distinction" do
      SpellEffectOverride.load_all()
      assert SpellEffectOverride.bonus_coefficient(10_917, 0) == 0.429
      assert SpellEffectOverride.bonus_coefficient(10_929, 0) == 0.2
      assert SpellEffectOverride.bonus_coefficient(25_292, 0) == 0.714
      assert SpellEffectOverride.bonus_coefficient(19_993, 0) == 0.429

      for id <- [19_750, 19_939, 19_940, 19_941, 19_942, 19_943] do
        assert SpellEffectOverride.bonus_coefficient(id, 0) == 0.0
      end
    end
  end
end
