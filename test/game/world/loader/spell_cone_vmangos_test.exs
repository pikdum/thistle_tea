defmodule ThistleTea.Game.World.Loader.SpellConeVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :vmangos_db

  describe "cone_degrees/1" do
    test "loads narrow, wide, and rear arcs with a sixty-degree default" do
      SpellEffectOverride.load_all()
      assert SpellEffectOverride.cone_degrees(24_933) == 7
      assert SpellEffectOverride.cone_degrees(25_030) == 90
      assert SpellEffectOverride.cone_degrees(15_847) == -120
      assert SpellEffectOverride.cone_degrees(0) == 60
    end
  end
end
