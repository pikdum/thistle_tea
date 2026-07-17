defmodule ThistleTea.Game.Spell.ScriptsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Scripts

  test "druid finishers are derived from family flags" do
    assert Scripts.finisher?(%Spell{spell_family: 7, family_flags_0: 0x00800000})
    refute Scripts.finisher?(%Spell{spell_family: 7, family_flags_0: 0x00400000})
  end

  describe "apply_trigger/1" do
    test "Power Word: Shield triggers Weakened Soul for every rank" do
      assert Scripts.apply_trigger(%Spell{id: 17}) == 6788
      assert Scripts.apply_trigger(%Spell{id: 10_901, first_in_chain: 17}) == 6788
    end

    test "unscripted spells trigger nothing" do
      assert Scripts.apply_trigger(%Spell{id: 133}) == nil
      assert Scripts.apply_trigger(%Spell{id: 116, first_in_chain: 116}) == nil
    end
  end

  describe "exclusive_category/1" do
    test "classifies mage armors by family flags" do
      row = dbc_row(spell_class_set: 3, spell_class_mask_0: 0x02000000)

      assert Scripts.exclusive_category(row) == :mage_armor
    end

    test "classifies warlock armors by visual and icon" do
      row = dbc_row(spell_visual_0: 130, spell_icon: 89)

      assert Scripts.exclusive_category(row) == :warlock_armor
    end

    test "leaves other spells uncategorized" do
      assert Scripts.exclusive_category(dbc_row([])) == nil
      assert Scripts.exclusive_category(dbc_row(spell_class_set: 3, spell_class_mask_0: 0x1)) == nil
    end
  end

  defp dbc_row(attrs) do
    Enum.into(attrs, %{spell_class_set: 0, spell_class_mask_0: 0, spell_visual_0: 0, spell_icon: 0})
  end
end
