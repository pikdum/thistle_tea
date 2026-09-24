defmodule ThistleTea.Game.World.Loader.SpellHealthFunnelDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "loads health funnels with their cadence and transfer ratio" do
      for {id, amount, multiple} <- [{24_322, 199, 5.0}, {24_617, 499, 10.0}] do
        spell = SpellLoader.load(id)
        effect = Enum.find(spell.effects, &(&1.aura == :periodic_health_funnel))
        assert effect.base_points == amount
        assert effect.amplitude_ms == 1_000
        assert effect.multiple_value == multiple
      end
    end
  end
end
