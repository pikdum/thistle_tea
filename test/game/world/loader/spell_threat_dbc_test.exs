defmodule ThistleTea.Game.World.Loader.SpellThreatDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.SpellThreat
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db

  setup [:modifier_mask_fixture]

  describe "load/1" do
    test "Plagueheart reduces critical spell threat and selected periodic spells separately" do
      caster = %Mob{unit: %Unit{level: 60, health: 100, max_health: 100, auras: []}}
      {caster, _events} = Aura.apply_spell(caster, 1, 60, SpellLoader.load(28_746), 0)
      projection = SpellThreat.projection(caster)
      assert projection.critical_modifiers == [{126, -25}]

      for {id, normal, critical} <- [{686, 1.0, 0.75}, {172, 0.75, 0.5625}] do
        spell = SpellLoader.load(id)
        context = SpellThreat.put_context(%CastContext{}, spell, projection)
        assert SpellThreat.multiplier(context) == normal
        assert SpellThreat.multiplier(context, true) == critical
      end

      {caster, _events} = Aura.apply_spell(caster, 1, 60, SpellLoader.load(1_038), 0)
      context = SpellThreat.put_context(%CastContext{}, SpellLoader.load(172), SpellThreat.projection(caster))
      assert_in_delta SpellThreat.multiplier(context), 0.525, 0.0001
      {caster, _events} = Aura.remove_spells(caster, [28_746], 1)
      context = SpellThreat.put_context(context, SpellLoader.load(172), SpellThreat.projection(caster))
      assert_in_delta SpellThreat.multiplier(context), 0.7, 0.0001
    end

    test "loads helpful-threat suppression independently from initial threat" do
      assert Spell.attribute?(SpellLoader.load(1_943), :no_helpful_threat)
      refute Spell.attribute?(SpellLoader.load(635), :no_helpful_threat)
    end
  end

  defp modifier_mask_fixture(_context) do
    key = {:class_masks, 28_746}
    previous = :ets.lookup(SpellEffectOverride, key)
    :ets.insert(SpellEffectOverride, {key, {0, 4_294_968_326, 0}})

    on_exit(fn ->
      :ets.delete(SpellEffectOverride, key)
      :ets.insert(SpellEffectOverride, previous)
    end)

    :ok
  end
end
