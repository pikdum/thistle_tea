defmodule ThistleTea.Game.World.Loader.SpellPercentDamageDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "loads percentage damage and cadence for every vanilla spell using aura 89" do
      for {id, index, percent, interval} <- [
            {23_072, 1, 20, 4_000},
            {23_127, 0, 5, 3_000},
            {23_449, 0, 10, 2_000},
            {24_910, 0, 20, 2_000},
            {25_838, 1, 90, 20_000}
          ] do
        spell = SpellLoader.load(id)
        effect = Enum.find(spell.effects, &(&1.aura == :periodic_damage_percent))
        assert effect.index == index
        assert Effect.roll(effect, 0) == percent
        assert effect.amplitude_ms == interval
      end
    end
  end
end
