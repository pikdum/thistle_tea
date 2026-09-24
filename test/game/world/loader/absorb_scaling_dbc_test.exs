defmodule ThistleTea.Game.World.Loader.AbsorbScalingDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.AbsorbBonus
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "shield and ward ranks retain their vanilla coefficient selectors" do
      context = %CastContext{healing_bonus: 1_000, spell_damage_bonus: %{fire: 200, frost: 300, shadow: 400}}

      for {id, expected} <- [
            {17, 47.5},
            {592, 70},
            {600, 92.5},
            {3747, 100},
            {10_901, 100},
            {543, 20},
            {10_225, 20},
            {6143, 30},
            {28_609, 30},
            {6229, 40},
            {11_739, 40},
            {11_740, 40},
            {28_610, 40},
            {1463, 0},
            {10_193, 0}
          ] do
        spell = SpellLoader.load(id)
        effect = Enum.find(spell.effects, &(&1.aura in [:school_absorb, :mana_shield]))
        assert_in_delta AbsorbBonus.value(spell, effect, context), expected, 0.0001, "#{spell.name} #{id}"
      end
    end
  end
end
