defmodule ThistleTea.Game.Entity.Logic.SpellAmountModifiersTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:entities]

  describe "receive/4" do
    test "fixed damage and healing keep base modifiers but bypass outgoing bonuses", %{caster: caster, target: target} do
      target = %{target | unit: %{target.unit | auras: []}}

      for type <- [:school_damage, :heal] do
        spell = %{spell(type) | custom_flags: 0x10}
        context = CastContext.from_caster(caster, spell, 2)
        {changed, events} = SpellEffect.receive(target, context, spell, 0)

        if type == :school_damage do
          assert changed.unit.health == 4_820
          assert [%Effects.SpellDamage{damage: 180}] = events
        else
          assert changed.unit.health == 5_180
          assert Enum.any?(events, &match?(%Effects.SpellHeal{damage: 180}, &1))
        end
      end
    end

    test "direct damage and healing apply each modifier to its actual amount", %{caster: caster, target: target} do
      for type <- [:school_damage, :heal] do
        spell = spell(type)
        context = CastContext.from_caster(caster, spell, 2)
        {changed, events} = SpellEffect.receive(target, context, spell, 0)

        if type == :school_damage do
          assert changed.unit.health == 4_160
          assert [%Effects.SpellDamage{damage: 840}] = events
        else
          assert changed.unit.health == 5_840
          assert Enum.any?(events, &match?(%Effects.SpellHeal{damage: 840}, &1))
        end
      end
    end

    test "resource gains use all-effects bonuses without damage or healing bonuses", %{caster: caster, target: target} do
      spell = spell(:energize)
      context = CastContext.from_caster(caster, spell, 2)
      {restored, _events} = SpellEffect.receive(target, context, spell, 0)
      assert restored.unit.power1 == 280
      assert restored.unit.health == target.unit.health
    end

    test "flat damage modifiers apply after chain attenuation", %{caster: caster, target: target} do
      spell = spell(:school_damage)
      context = %{CastContext.from_caster(caster, spell, 2) | chain_effects: %{0 => 0.5}}
      {changed, [%Effects.SpellDamage{damage: damage}]} = SpellEffect.receive(target, context, spell, 0)
      assert damage in [468, 469]
      assert changed.unit.health == target.unit.health - damage
    end
  end

  describe "tick/2" do
    test "fixed periodic effects and Ignite bypass outgoing amount modifiers", %{caster: caster, target: target} do
      for spell <- [
            %{periodic_spell(:periodic_damage) | custom_flags: 0x10},
            %{periodic_spell(:periodic_heal) | custom_flags: 0x10},
            %{periodic_spell(:periodic_damage) | id: 12_654}
          ] do
        spell = %{spell | effects: [%{hd(spell.effects) | bonus_coefficient: 0.0}]}
        context = CastContext.from_caster(caster, spell, 2)
        {applied, _events} = Aura.apply_spell(target, context, spell, 0)
        assert hd(List.last(applied.unit.auras).auras).amount == 180
      end
    end

    test "periodic amounts use dot modifiers after caster bonuses and keep their snapshot", %{
      caster: caster,
      target: target
    } do
      for type <- [:periodic_damage, :periodic_heal] do
        spell = periodic_spell(type)
        context = CastContext.from_caster(caster, spell, 2)
        {applied, _events} = Aura.apply_spell(target, context, spell, 0)
        assert hd(List.last(applied.unit.auras).auras).amount == 408
        {ticked, events} = Aura.tick(applied, 1_000)

        if type == :periodic_damage do
          assert ticked.unit.health == 4_358
          assert [%Effects.SpellDamage{damage: 642}] = events
        else
          assert ticked.unit.health == 5_642
          assert Enum.any?(events, &match?(%Effects.PeriodicAuraLog{amount: 642}, &1))
        end

        {removed, _events} = Aura.remove_spells(ticked, [spell.id], 1_500)
        assert {^removed, []} = Aura.tick(removed, 2_000)
        unbuffed = %{caster | unit: %{caster.unit | auras: []}}
        context = CastContext.from_caster(unbuffed, spell, 2)
        {refreshed, _events} = Aura.apply_spell(ticked, context, spell, 1_500)
        assert hd(List.last(refreshed.unit.auras).auras).amount == 140
      end
    end

    test "direct damage modifiers do not amplify a periodic component", %{caster: caster, target: target} do
      caster = %{caster | unit: %{caster.unit | auras: [modifier(:add_flat_modifier, 0, 50)]}}
      spell = periodic_spell(:periodic_damage)
      context = CastContext.from_caster(caster, spell, 2)
      {applied, _events} = Aura.apply_spell(target, context, spell, 0)
      assert hd(List.last(applied.unit.auras).auras).amount == 140
    end
  end

  defp entities(_context) do
    caster = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{
        level: 60,
        health: 5_000,
        max_health: 10_000,
        equipment_bonuses: %{spell_fire: 40, healing: 40},
        auras: [
          modifier(:add_flat_modifier, 8, 20),
          modifier(:add_pct_modifier, 8, 50),
          modifier(:add_flat_modifier, 0, 30),
          modifier(:add_pct_modifier, 0, 50),
          modifier(:add_flat_modifier, 22, 10),
          modifier(:add_pct_modifier, 22, 20),
          aura(:mod_damage_percent_done, 50),
          aura(:mod_healing_done_percent, 50)
        ]
      },
      internal: %Internal{}
    }

    target = %{
      caster
      | object: %Object{guid: 2},
        unit: %{
          caster.unit
          | equipment_bonuses: %{},
            power_type: 0,
            power1: 100,
            max_power1: 1_000,
            auras: [
              aura(:mod_damage_taken, 20),
              aura(:mod_damage_percent_taken, 50),
              aura(:mod_healing, 20),
              aura(:mod_healing_pct, 50)
            ]
        }
    }

    %{caster: caster, target: target}
  end

  defp spell(type) do
    %Spell{
      id: 90_001,
      dmg_class: 1,
      school: :fire,
      spell_family: 3,
      family_flags_0: 1,
      duration_ms: 3_000,
      effects: [%Effect{index: 0, type: type, base_points: 100, bonus_coefficient: 1.0, misc_value: 0}]
    }
  end

  defp periodic_spell(type) do
    spell = spell(:apply_aura)
    %{spell | effects: [%{hd(spell.effects) | aura: type, amplitude_ms: 1_000}]}
  end

  defp modifier(type, operation, amount) do
    holder = aura(type, amount)
    %{holder | auras: [%{hd(holder.auras) | misc_value: operation, class_mask: 1}]}
  end

  defp aura(type, amount) do
    %Holder{
      spell: %Spell{id: System.unique_integer([:positive]), spell_family: 3},
      auras: [%AuraData{type: type, amount: amount, misc_value: 4}]
    }
  end
end
