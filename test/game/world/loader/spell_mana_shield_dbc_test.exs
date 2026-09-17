defmodule ThistleTea.Game.World.Loader.SpellManaShieldDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db

  setup [:modifier_masks]

  describe "load/1" do
    test "all vanilla Mana Shield ranks absorb physical damage at two mana per point" do
      for id <- [1463, 8494, 8495, 10_191, 10_192, 10_193] do
        spell = SpellLoader.load(id)
        assert [%{aura: :mana_shield, misc_value: 1, multiple_value: 2.0}] = spell.effects
      end
    end

    test "Improved Mana Shield applies both ranks to a live shield" do
      for {id, expected_mana} <- [{11_252, 146}, {12_605, 152}] do
        entity = %{object: %Object{guid: 1}, unit: %Unit{level: 50, auras: [], power1: 200}}
        context = %CastContext{caster_guid: 1, caster_level: 50}
        {entity, _events} = Aura.apply_spell(entity, context, SpellLoader.load(1463), 100)
        {entity, _events} = Aura.apply_spell(entity, context, SpellLoader.load(id), 101)
        {entity, 0} = Aura.absorb_damage(entity, 30, :physical, 102)
        assert entity.unit.power1 == expected_mana
      end
    end
  end

  defp modifier_masks(_context) do
    for id <- [11_252, 12_605] do
      key = {:class_masks, id}
      previous = :ets.lookup(SpellEffectOverride, key)
      :ets.insert(SpellEffectOverride, {key, {32_768, 0, 0}})

      on_exit(fn ->
        :ets.delete(SpellEffectOverride, key)
        :ets.insert(SpellEffectOverride, previous)
      end)
    end

    :ok
  end
end
