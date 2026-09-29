defmodule ThistleTea.Game.Core.Spell.ConsumableTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Spell.Consumable

  describe "category/1" do
    test "recognizes seated recovery across effect slots and percentage variants" do
      assert Consumable.category(recovery_row(%{effect_aura_2: 84})) == :food
      assert Consumable.category(recovery_row(%{effect_aura_0: 20})) == :food
      assert Consumable.category(recovery_row(%{effect_aura_1: 85})) == :drink
      assert Consumable.category(recovery_row(%{effect_aura_2: 21})) == :drink

      assert Consumable.category(recovery_row(%{effect_aura_0: 20, effect_aura_1: 21})) == :food_and_drink
    end

    test "separates the eating aura from its lasting buff" do
      row = recovery_row(%{effect_aura_0: 84, attributes_ex2: 0x80000000})
      assert Consumable.category(row) == :food
      assert Consumable.category(%{row | aura_interrupt_flags: 0}) == :well_fed
    end

    test "does not classify ordinary regeneration or other families as food" do
      assert Consumable.category(%{spell_class_set: 0, effect_aura_0: 84}) == nil
      assert Consumable.category(recovery_row(%{spell_class_set: 13, effect_aura_0: 84})) == nil
      assert Consumable.category(recovery_row(%{effect_aura_0: 29})) == nil
    end

    test "recognizes the priest-family fruit buffs without capturing class spells" do
      row = %{spell_class_set: 6, spell_icon: 52, attributes: 0x08000000, interrupt_flags: 8}
      assert Consumable.category(row) == :well_fed
      assert Consumable.category(%{row | spell_icon: 79}) == :well_fed
      assert Consumable.category(%{row | interrupt_flags: 0}) == nil
      assert Consumable.category(%{row | attributes: 0}) == nil
    end
  end

  describe "elixir_category/1" do
    test "uses both flask bits and preserves vanilla elixir coexistence" do
      assert Consumable.elixir_category(3) == :flask
      assert Consumable.elixir_category(16) == :well_fed
      assert Consumable.elixir_category(19) == :flask
      for mask <- [0, 1, 2], do: assert(Consumable.elixir_category(mask) == nil)
    end
  end

  defp recovery_row(fields), do: Map.merge(%{spell_class_set: 0, aura_interrupt_flags: 0x40000}, fields)
end
