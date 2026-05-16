defmodule ThistleTea.Game.SpellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell

  describe "school_mask/1" do
    test "returns bit masks for spell schools" do
      assert Spell.school_mask(:physical) == 1
      assert Spell.school_mask(:frost) == 16
      assert Spell.school_mask(%Spell{school: :arcane}) == 64
    end

    test "returns zero for unknown school data" do
      assert Spell.school_mask(nil) == 0
    end
  end

  describe "school_index/1" do
    test "returns packet indexes for spell schools" do
      assert Spell.school_index(:physical) == 0
      assert Spell.school_index(:frost) == 4
      assert Spell.school_index(%Spell{school: :arcane}) == 6
    end

    test "preserves integer school values" do
      assert Spell.school_index(7) == 7
    end
  end
end
