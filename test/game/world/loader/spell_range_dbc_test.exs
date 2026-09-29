defmodule ThistleTea.Game.World.Loader.SpellRangeDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell.Range
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db

  setup [:range_masks]

  describe "load/1" do
    test "vanilla talents and equipment passives modify their intended spell ranges" do
      caster = %Mob{object: %Object{guid: 1}, unit: %Unit{level: 60, auras: []}, internal: %Internal{}}

      for {modifier_id, spell_id, expected} <- [
            {12_353, 133, 41.0},
            {16_758, 116, 36.0},
            {16_820, 5176, 36.0},
            {17_325, 589, 36.0},
            {17_918, 686, 36.0},
            {18_219, 172, 36.0},
            {19_500, 75, 41.0},
            {23_560, 136, 30.0},
            {24_462, 403, 35.0},
            {24_482, 585, 35.0},
            {27_790, 585, 36.0},
            {29_000, 403, 36.0}
          ] do
        modifier = SpellLoader.load(modifier_id)
        spell = SpellLoader.load(spell_id)
        {modified, _events} = Aura.apply_spell(caster, 1, 60, modifier, 0)
        assert Range.maximum(modified, spell) == expected, "#{modifier.name}: #{spell.name}"

        {reset, _events} = Aura.remove_spells(modified, [modifier_id], 1)
        assert Range.maximum(reset, spell) == spell.range_yards
      end
    end
  end

  defp range_masks(_context) do
    for {spell_id, mask} <- [{18_219, 6_447_219_738}, {29_000, 3}] do
      key = {:class_masks, spell_id}
      previous = :ets.lookup(SpellEffectOverride, key)
      :ets.insert(SpellEffectOverride, {key, {mask, 0, 0}})

      on_exit(fn ->
        :ets.delete(SpellEffectOverride, key)
        :ets.insert(SpellEffectOverride, previous)
      end)
    end

    :ok
  end
end
