defmodule ThistleTea.Game.World.Loader.SpellHealthFunnelDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db
  @spell_ids [24_322, 24_617]

  setup [:isolate_dbc_effects]

  describe "load/1" do
    test "loads original DBC health funnels with their cadence and transfer ratio" do
      for {id, amount, multiple} <- [{24_322, 199, 5.0}, {24_617, 499, 10.0}] do
        spell = SpellLoader.load(id)
        effect = Enum.find(spell.effects, &(&1.aura == :periodic_health_funnel))
        assert effect.base_points == amount
        assert effect.amplitude_ms == 1_000
        assert effect.multiple_value == multiple
      end
    end
  end

  defp isolate_dbc_effects(_context) do
    saved = Enum.flat_map(@spell_ids, &:ets.take(SpellEffectOverride, {:mods, &1}))

    on_exit(fn ->
      Enum.each(@spell_ids, &:ets.delete(SpellEffectOverride, {:mods, &1}))
      :ets.insert(SpellEffectOverride, saved)
    end)

    :ok
  end
end
