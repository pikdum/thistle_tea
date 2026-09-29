defmodule ThistleTea.Game.World.Loader.SpellRefundsDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "vanilla builders and rage attacks opt in while finishers do not" do
      for id <- [1752, 53, 1822, 78, 23_922] do
        spell = SpellLoader.load(id)
        assert Spell.attribute?(spell, :discount_power_on_miss)
        assert spell.power_type in [1, 3]
      end

      for id <- [2098, 6760, 22_568] do
        spell = SpellLoader.load(id)
        assert Spell.attribute?(spell, :finishing_move)
        refute Spell.attribute?(spell, :discount_power_on_miss)
      end
    end
  end
end
