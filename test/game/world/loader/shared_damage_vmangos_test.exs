defmodule ThistleTea.Game.World.Loader.SharedDamageVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.World.Loader.SpellScriptName

  @moduletag :vmangos_db

  describe "get/1" do
    test "the supported build assigns shared damage to Meteors and the player trinket" do
      SpellScriptName.load_all()

      for id <- [24_340, 26_558, 26_789, 28_884] do
        assert SpellScriptName.get(id) == "spell_meteor"
      end

      item = Mangos.Repo.get(Mangos.ItemTemplate, 21_891)
      assert item.spellid_1 == 26_789
    end
  end
end
