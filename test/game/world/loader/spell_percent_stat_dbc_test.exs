defmodule ThistleTea.Game.World.Loader.SpellPercentStatDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "decodes stat percentages and signed selectors from vanilla spells" do
      for {id, amount, stat} <- [
            {2146, -75, -1},
            {11_630, -50, -1},
            {11_631, -25, -1},
            {15_007, -75, -1},
            {16_734, 2, 3},
            {16_735, 2, 3},
            {16_736, 2, 3},
            {16_737, 2, 3},
            {16_738, 2, 3},
            {23_735, 10, 0},
            {23_736, 10, 1},
            {23_737, 10, 2},
            {23_738, 10, 4},
            {23_766, 10, 3},
            {24_705, 25, 2},
            {26_035, 10, -1},
            {26_393, 10, -1},
            {26_462, 10, -1}
          ] do
        effect = Enum.find(SpellLoader.load(id).effects, &(&1.aura == :mod_percent_stat))
        assert effect.misc_value == stat
        assert Effect.roll(effect, 0) == amount
      end
    end
  end
end
