defmodule ThistleTea.Game.World.Loader.EnchantmentsDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemEnchantment
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.EquipmentEnchantments
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: EnchantmentLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "loads the real bracer enchant, target mask, rod and recipe thresholds" do
      spell = SpellLoader.load(7418)
      assert spell.tools == [6218]
      assert spell.equipped_item_class == 4
      assert spell.equipped_item_inventory_type_mask == Bitwise.bsl(1, 9)
      assert Enum.any?(spell.effects, &(&1.type == :enchant_item and &1.misc_value == 41))
      assert EnchantmentLoader.recipe(7418) == %{skill_id: 333, yellow: 70, gray: 110}
    end

    test "real Minor Health and Greater Intellect equip spells derive player stats" do
      character = %Character{
        object: %Object{guid: 1},
        player: %Player{},
        internal: %Internal{},
        movement_block: %MovementBlock{},
        unit: %Unit{
          health: 100,
          base_health: 100,
          max_health: 100,
          base_intellect: 20,
          intellect: 20,
          auras: [],
          level: 60
        }
      }

      item = Item.build(%ItemTemplate{entry: 100}, 10)

      for {spell_id, field, expected} <- [{7419, :max_health, 105}, {13_825, :intellect, 27}] do
        enchantment = %ItemEnchantment{effects: [%{type: 3, spell_id: spell_id}]}
        equipped = EquipmentEnchantments.sync(character, [{:wrists, item, 0, enchantment}], &SpellLoader.load/1, 0)
        assert Map.fetch!(equipped.unit, field) == expected
        assert EquipmentEnchantments.sync(equipped, [], &SpellLoader.load/1, 10).unit.intellect == 20
      end
    end
  end
end
