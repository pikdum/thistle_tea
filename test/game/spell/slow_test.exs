defmodule ThistleTea.Game.Spell.SlowTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell.Slow

  describe "category/1" do
    test "recognizes snares alongside direct damage in either effect order" do
      assert Slow.category(%{effect_0: 6, effect_aura_0: 33, effect_1: 2}) == :snare
      assert Slow.category(%{effect_0: 2, effect_1: 6, effect_aura_1: 33}) == :snare
    end

    test "only negative melee haste uses the exclusive penalty category" do
      row = %{effect_0: 6, effect_aura_0: 138, effect_base_points_0: -11}
      assert Slow.category(row) == :negative_haste
      assert Slow.category(%{row | effect_base_points_0: 20}) == nil
    end

    test "preserves daze, potion-family effects, and spells carrying another aura" do
      snare = %{effect_0: 6, effect_aura_0: 33}
      assert Slow.category(Map.put(snare, :attributes_ex1, 0x40000)) == nil
      assert Slow.category(Map.put(snare, :spell_class_set, 13)) == nil
      assert Slow.category(Map.merge(snare, %{effect_1: 6, effect_aura_1: 3})) == nil

      assert Slow.category(%{
               effect_0: 6,
               effect_aura_0: 138,
               effect_base_points_0: -11,
               effect_1: 6,
               effect_aura_1: 65
             }) == nil
    end
  end
end
