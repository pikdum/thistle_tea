defmodule ThistleTea.Game.World.Loader.DeathRayVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.World.Loader.SpellScriptName

  @moduletag :vmangos_db

  describe "get/1" do
    test "the engineering trinket connects to both reference scripts" do
      SpellScriptName.load_all()
      assert SpellScriptName.get(13_278) == "spell_gdr_channel"
      assert SpellScriptName.get(13_493) == "spell_gdr_periodic"
      item = Mangos.Repo.get(Mangos.ItemTemplate, 10_645)
      assert item.spellid_1 == 13_278
      assert item.spellcooldown_1 == 300_000
    end
  end
end
