defmodule ThistleTea.Game.World.Loader.ReactiveArmorVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.SpellProcEvent

  @moduletag :vmangos_db

  describe "load_all/0" do
    test "the breastplate equips Obsidian Armor with its ten-second proc cooldown" do
      item = ItemLoader.get_template(22_196)
      assert item.spellid_1 == 27_539
      assert item.spelltrigger_1 == 1
      SpellProcEvent.load_all()
      assert SpellProcEvent.get(27_539).cooldown_ms == 10_000
    end
  end
end
