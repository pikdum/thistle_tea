defmodule ThistleTea.Game.World.Loader.SelfResurrectionDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db
  @spell_ids [3026, 20_758, 20_759, 20_760, 20_761, 21_169, 16_184, 16_209]

  setup [:cache_spell_fixtures]

  describe "load/1" do
    test "loads flat restoration for every Soulstone rank" do
      for {id, health, mana} <- [
            {3026, 400, 700},
            {20_758, 750, 1_200},
            {20_759, 1_100, 1_700},
            {20_760, 1_600, 2_200},
            {20_761, 2_200, 2_800}
          ] do
        spell = SpellLoader.load(id)
        assert [%Effect{type: :self_resurrect} = effect] = spell.effects
        assert Effect.roll(effect, 0) == -health
        assert effect.misc_value == mana
        assert spell.reagents == []
      end
    end

    test "loads Reincarnation's percentage, reagent, and shared cooldown" do
      spell = SpellLoader.load(21_169)
      assert [%Effect{type: :self_resurrect} = effect] = spell.effects
      assert Effect.roll(effect, 0) == 20
      assert spell.reagents == [{17_030, 1}]
      assert spell.category == 1161
      assert spell.category_recovery_time_ms == 3_600_000
    end

    test "loads both Improved Reincarnation modifiers" do
      for {id, cooldown, restoration} <- [{16_184, -600_000, 10}, {16_209, -1_200_000, 20}] do
        spell = SpellLoader.load(id)
        cooldown_effect = Enum.find(spell.effects, &(&1.misc_value == 11))
        restoration_effect = Enum.find(spell.effects, &(&1.misc_value == 8))
        assert Effect.roll(cooldown_effect, 0) == cooldown
        assert Effect.roll(restoration_effect, 0) == restoration
      end
    end
  end

  defp cache_spell_fixtures(_context) do
    entries =
      for id <- @spell_ids,
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
