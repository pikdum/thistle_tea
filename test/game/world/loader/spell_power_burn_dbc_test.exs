defmodule ThistleTea.Game.World.Loader.SpellPowerBurnDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "loads periodic power burns with their conversion and cadence" do
      for {id, amount, interval, multiple} <- [
            {19_659, 399, 3000, 1.0},
            {23_153, 49, 1000, 0.0},
            {24_619, 499, 2000, 1.0}
          ] do
        spell = SpellLoader.load(id)
        effect = Enum.find(spell.effects, &(&1.aura == :periodic_power_burn))
        assert effect.base_points == amount
        assert effect.amplitude_ms == interval
        assert effect.multiple_value == multiple
        assert effect.misc_value == 0
      end
    end
  end
end
