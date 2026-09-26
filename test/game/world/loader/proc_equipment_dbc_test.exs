defmodule ThistleTea.Game.World.Loader.ProcEquipmentDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "real weapon talents require equipment while defensive shield spells are exempt" do
      for id <- [12_281, 12_284, 12_834, 12_867, 13_964] do
        spell = SpellLoader.load(id)
        assert spell.equipped_item_class == 2
        refute Spell.attribute?(spell, :no_proc_equip_requirement)
      end

      for id <- [2565, 20_127, 20_928] do
        spell = SpellLoader.load(id)
        assert spell.equipped_item_class == 4
        assert Spell.attribute?(spell, :no_proc_equip_requirement)
      end
    end
  end
end
