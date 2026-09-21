defmodule ThistleTea.Game.World.Loader.SpellMeleeRangeDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "distinguishes queued combat-range attacks from other short-range spells" do
      for id <- [78, 11_566, 845, 6807] do
        spell = SpellLoader.load(id)
        assert spell.melee_range?
        assert Spell.attribute?(spell, :on_next_swing)
      end

      short_range = SpellLoader.load(5422)
      assert short_range.range_yards == 5.0
      assert Spell.attribute?(short_range, :on_next_swing)
      refute short_range.melee_range?
      refute SpellLoader.load(133).melee_range?
    end
  end
end
