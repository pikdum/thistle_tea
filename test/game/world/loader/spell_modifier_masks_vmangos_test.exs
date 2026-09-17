defmodule ThistleTea.Game.World.Loader.SpellModifierMasksVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :vmangos_db

  describe "load_all/0" do
    test "loads vanilla Vile Poisons masks from the latest supported build" do
      SpellEffectOverride.load_all()

      assert SpellEffectOverride.class_mask(16_720, 0) == 73_728
      assert SpellEffectOverride.class_mask(16_720, 1) == 65_536
      assert SpellEffectOverride.class_mask(16_720, 2) == 268_550_144

      assert SpellEffectOverride.class_mask(999_999, 0) == nil
    end
  end
end
