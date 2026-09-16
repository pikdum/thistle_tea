defmodule ThistleTea.Game.World.Loader.MechanicResistanceDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos.SpellEffectMod
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db

  setup [:cache_spell_fixtures]

  describe "load/1" do
    test "loads Hardiness and Frostbolt's effect mechanic" do
      hardiness = SpellLoader.load(20_573)
      frostbolt = SpellLoader.load(116)

      assert [%Effect{aura: :mechanic_resistance, misc_value: 12, base_points: 24, base_dice: 1}] = hardiness.effects
      assert frostbolt.mechanic == 0
      assert %Effect{mechanic: 11} = Enum.find(frostbolt.effects, &(&1.index == 0))
    end

    test "honors an explicit VMangos effect mechanic override including zero" do
      :ets.insert(SpellEffectOverride, {{:mods, 116}, %{0 => %SpellEffectMod{effect_mechanic: 12}}})
      assert %Effect{mechanic: 12} = Enum.find(SpellLoader.load(116).effects, &(&1.index == 0))

      :ets.insert(SpellEffectOverride, {{:mods, 116}, %{0 => %SpellEffectMod{effect_mechanic: 0}}})
      assert %Effect{mechanic: 0} = Enum.find(SpellLoader.load(116).effects, &(&1.index == 0))
    end
  end

  defp cache_spell_fixtures(_context) do
    entries =
      for id <- [116, 20_573],
          {table, prefix, value} <- [{SpellChain, :chain, nil}, {SpellEffectOverride, :mods, %{}}],
          do: {table, {prefix, id}, value}

    previous = for {table, key, _value} <- entries, do: {table, key, :ets.lookup(table, key)}

    Enum.each(entries, fn {table, key, value} -> :ets.insert(table, {key, value}) end)

    on_exit(fn ->
      Enum.each(previous, fn {table, key, rows} ->
        :ets.delete(table, key)
        :ets.insert(table, rows)
      end)
    end)

    :ok
  end
end
