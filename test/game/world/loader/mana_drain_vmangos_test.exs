defmodule ThistleTea.Game.World.Loader.ManaDrainVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.EquipmentSpells
  alias ThistleTea.Game.World.Loader.Item
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :vmangos_db

  describe "get_template/1" do
    test "Black Grasp equips the mana proc and its resource spells have no spell-power scaling" do
      assert %ItemTemplate{inventory_type: 10, spellid_3: 27_522, spelltrigger_3: 1} = item = Item.get_template(22_194)
      assert 27_522 in EquipmentSpells.spell_ids(item)
      SpellEffectOverride.load_all()
      assert SpellEffectOverride.bonus_coefficient(27_526, 0) == 0.0
      assert SpellEffectOverride.bonus_coefficient(29_471, 0) == 0.0
    end
  end
end
