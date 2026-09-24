defmodule ThistleTea.Game.Entity.Logic.Aura.ModifiersTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:entities]

  describe "apply_spell/4" do
    test "fractional attack power survives aggregation before the final unit projection", %{target: target} do
      holders =
        for id <- [1, 2],
            do: %Holder{
              spell: %Spell{id: id},
              auras: [%Aura{type: :mod_attack_power, amount: 9.5}]
            }

      assert Stats.recompute(%{target.unit | auras: holders}).attack_power == 219
    end

    test "fractional haste reaches both weapon and casting periods", %{caster: caster, target: target} do
      caster = %{caster | unit: %{caster.unit | auras: [modifier(23, 6)]}}

      for type <- [:mod_melee_haste, :mod_casting_speed] do
        spell = spell(type, 30)
        context = CastContext.from_caster(caster, spell, 2)
        {applied, _events} = AuraLogic.apply_spell(target, context, spell, 1_000)
        assert hd(hd(applied.unit.auras).auras).amount == 31.8

        if type == :mod_melee_haste,
          do: assert(applied.unit.base_attack_time == 1_517),
          else: assert_in_delta(applied.unit.mod_cast_speed, 100 / 131.8, 0.000001)
      end
    end

    test "attack power operations follow all-effects modifiers and feed derived stats", %{
      caster: caster,
      target: target
    } do
      caster = %{caster | unit: %{caster.unit | auras: [modifier(8, 100), modifier(3, 10, :add_flat_modifier)]}}

      for {type, field, base, expected} <- [
            {:mod_attack_power, :attack_power, 200, 410},
            {:mod_ranged_attack_power, :ranged_attack_power, 100, 310},
            {:mod_attack_power_pct, :attack_power, 200, 620},
            {:mod_ranged_attack_power_pct, :ranged_attack_power, 100, 310}
          ] do
        spell = spell(type, 100)
        context = CastContext.from_caster(caster, spell, 2)
        {applied, _events} = AuraLogic.apply_spell(target, context, spell, 1_000)
        assert [%Holder{auras: [%Aura{amount: amount}]}] = applied.unit.auras
        assert amount == 210
        assert Map.fetch!(applied.unit, field) == expected
        assert Stats.recompute(applied.unit) == applied.unit

        {removed, _events} = AuraLogic.remove_spells(applied, [spell.id], 2_000)
        assert Map.fetch!(removed.unit, field) == base
      end
    end

    test "haste modifiers affect every speed aura while preserving signed slow penalties", %{
      caster: caster,
      target: target
    } do
      caster = %{caster | unit: %{caster.unit | auras: [modifier(23, 10, :add_flat_modifier)]}}

      for {type, field} <- [
            {:mod_attack_speed, :base_attack_time},
            {:mod_melee_haste, :base_attack_time},
            {:mod_ranged_haste, :ranged_attack_time},
            {:mod_casting_speed, :mod_cast_speed}
          ],
          amount <- [40, -40] do
        spell = spell(type, amount)
        context = CastContext.from_caster(caster, spell, 2)
        {applied, _events} = AuraLogic.apply_spell(target, context, spell, 1_000)
        assert hd(hd(applied.unit.auras).auras).amount == amount + 10
        factor = if amount > 0, do: 100 / 150, else: 1.3
        expected = if field == :mod_cast_speed, do: factor, else: trunc(2_000 * factor)
        assert Map.fetch!(applied.unit, field) == expected
      end
    end

    test "family and mask mismatches cannot alter aura potency", %{caster: caster, target: target} do
      caster = %{caster | unit: %{caster.unit | auras: [modifier(3, 50)]}}

      for spell <- [
            %{spell(:mod_attack_power, 100) | family_flags_0: 2},
            %{spell(:mod_attack_power, 100) | spell_family: 3}
          ] do
        context = CastContext.from_caster(caster, spell, 2)
        {applied, _events} = AuraLogic.apply_spell(target, context, spell, 1_000)
        assert applied.unit.attack_power == 300
      end
    end

    test "existing holders retain their snapshot until replaced or expired", %{caster: caster, target: target} do
      spell = spell(:mod_attack_power, 100)
      talented = %{caster | unit: %{caster.unit | auras: [modifier(3, 50)]}}
      context = CastContext.from_caster(talented, spell, 2)
      {applied, _events} = AuraLogic.apply_spell(target, context, spell, 1_000)
      assert applied.unit.attack_power == 350

      {unchanged, _events} = AuraLogic.expire_due(applied, 2_000)
      assert unchanged.unit.attack_power == 350
      context = CastContext.from_caster(caster, spell, 2)
      {replaced, _events} = AuraLogic.apply_spell(unchanged, context, spell, 3_000)
      assert replaced.unit.attack_power == 300
      assert length(replaced.unit.auras) == 1

      {expired, _events} = AuraLogic.expire_due(replaced, 13_000)
      assert expired.unit.attack_power == 200
      assert expired.unit.auras == []
    end
  end

  defp entities(_context) do
    entity = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{
        level: 60,
        base_attack_power: 200,
        base_ranged_attack_power: 100,
        base_melee_attack_time: 2_000,
        base_ranged_attack_time: 2_000,
        auras: []
      },
      internal: %Internal{}
    }

    %{caster: entity, target: %{entity | object: %Object{guid: 2}}}
  end

  defp spell(type, amount) do
    %Spell{
      id: 100,
      spell_family: 8,
      family_flags_0: 1,
      duration_ms: 10_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: type, base_points: amount}]
    }
  end

  defp modifier(operation, amount, type \\ :add_pct_modifier) do
    %Holder{
      spell: %Spell{id: operation, spell_family: 8},
      auras: [%Aura{type: type, misc_value: operation, amount: amount, class_mask: 1}]
    }
  end
end
