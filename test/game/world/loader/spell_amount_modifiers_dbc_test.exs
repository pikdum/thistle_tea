defmodule ThistleTea.Game.World.Loader.SpellAmountModifiersDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db

  setup [:warrior_modifier_masks, :entities]

  describe "load/1" do
    test "flat spell damage bonuses add points at both low and high ranks", %{caster: caster, target: target} do
      for {id, modifier, bonus} <- [{116, 21_229, 45}, {10_181, 21_229, 45}, {3110, 22_855, 8}, {6572, 28_844, 75}] do
        spell = SpellLoader.load(id)
        {buffed, _events} = Aura.apply_spell(caster, 1, 60, SpellLoader.load(modifier), 0)
        assert damage(target, buffed, spell) == damage(target, caster, spell) + bonus
      end
    end

    test "Bloodrage gains the flat rage from both Improved Bloodrage ranks", %{caster: caster} do
      spell = SpellLoader.load(2687)
      caster = %{caster | unit: %{caster.unit | power_type: 1, power2: 0, max_power2: 1_000}}

      for {modifier, expected} <- [{12_301, 120}, {12_818, 150}] do
        {buffed, _events} = Aura.apply_spell(caster, 1, 60, SpellLoader.load(modifier), 0)
        context = CastContext.from_caster(buffed, spell, 1)
        {restored, _events} = SpellEffect.receive(buffed, context, spell, 0)
        assert restored.unit.power2 == expected
      end
    end

    test "Fireball's periodic bonus changes only its periodic component", %{caster: caster, target: target} do
      spell = SpellLoader.load(133)
      {buffed, _events} = Aura.apply_spell(caster, 1, 60, SpellLoader.load(21_230), 0)
      assert damage(target, buffed, spell) == damage(target, caster, spell)
      {baseline, _events} = Aura.apply_spell(target, CastContext.from_caster(caster, spell, 2), spell, 0)
      {boosted, _events} = Aura.apply_spell(target, CastContext.from_caster(buffed, spell, 2), spell, 0)
      assert periodic_amount(boosted) == periodic_amount(baseline) + 24
    end
  end

  defp damage(target, caster, spell) do
    context = %{CastContext.from_caster(caster, spell, 2) | melee_crit_chance: 0, hit_chance_bonus: 100}
    :rand.seed(:exsss, {1, 2, 3})
    {_target, events} = SpellEffect.receive(target, context, spell, 0)
    [%Effects.SpellDamage{damage: damage}] = Enum.filter(events, &is_struct(&1, Effects.SpellDamage))
    damage
  end

  defp periodic_amount(target) do
    target.unit.auras
    |> Enum.flat_map(& &1.auras)
    |> Enum.find(&(&1.type == :periodic_damage))
    |> Map.fetch!(:amount)
  end

  defp entities(_context) do
    caster = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 10_000, max_health: 10_000, auras: []},
      internal: %Internal{}
    }

    target = %{caster | object: %Object{guid: 2}, unit: %{caster.unit | flags: 0x00040000}}
    %{caster: caster, target: target}
  end

  defp warrior_modifier_masks(_context) do
    for {id, mask} <- [{12_301, 256}, {12_818, 256}, {28_844, 1_024}] do
      key = {:class_masks, id}
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
