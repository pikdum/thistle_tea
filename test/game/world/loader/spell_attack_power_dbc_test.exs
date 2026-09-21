defmodule ThistleTea.Game.World.Loader.SpellAttackPowerDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "loads signed attack power buffs, debuffs, and percentages" do
      for {id, type, amount} <- [
            {1160, :mod_attack_power, -35},
            {11_556, :mod_attack_power, -140},
            {11_717, :mod_attack_power, 90},
            {25_289, :mod_attack_power, 232},
            {9199, :mod_attack_power_pct, 50}
          ] do
        effect = Enum.find(SpellLoader.load(id).effects, &(&1.aura == type))
        assert %Effect{} = effect
        assert Effect.roll(effect, 0) == amount
      end
    end
  end
end
