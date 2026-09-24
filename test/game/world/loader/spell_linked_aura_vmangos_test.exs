defmodule ThistleTea.Game.World.Loader.SpellLinkedAuraVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :vmangos_db

  describe "load_all/0" do
    test "loads Barkskin's linked aura from VMangos" do
      SpellEffectOverride.load_all()

      assert %{1 => %{effect: 6, effect_apply_aura_name: 192, effect_trigger_spell: 22_839}} =
               SpellEffectOverride.mods(22_812)
    end
  end
end
