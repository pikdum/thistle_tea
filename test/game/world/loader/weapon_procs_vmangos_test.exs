defmodule ThistleTea.Game.World.Loader.WeaponProcsVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Logic.WeaponProcs
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  @moduletag :vmangos_db

  describe "get_template/1" do
    test "preserves innate weapon spells and per-item PPM overrides" do
      for {entry, delay, spell, ppm} <- [
            {647, 2600, 17_152, 0.0},
            {1982, 2800, 18_211, 0.0},
            {19_019, 1900, 21_992, 8.0}
          ] do
        template = ItemLoader.get_template(entry)
        assert template.delay == delay
        assert WeaponProcs.spells(template) == [{spell, ppm}]
      end

      assert WeaponProcs.spells(ItemLoader.get_template(13_937)) == []
    end
  end
end
