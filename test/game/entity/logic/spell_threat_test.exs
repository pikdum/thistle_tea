defmodule ThistleTea.Game.Entity.Logic.SpellThreatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.DamageHeal
  alias ThistleTea.Game.Entity.Logic.SpellThreat
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:target]

  describe "put_context/3" do
    test "combines school, family and critical modifiers independently", %{target: target} do
      caster = %{target | unit: %{target.unit | auras: [modifiers()]}}
      spell = %Spell{id: 10, school: :shadow, spell_family: 5, family_flags_0: 2}
      context = SpellThreat.put_context(%CastContext{}, spell, SpellThreat.projection(caster))
      assert_in_delta SpellThreat.multiplier(context), 0.525, 0.0001
      assert_in_delta SpellThreat.multiplier(context, true), 0.39375, 0.0001

      physical = %{spell | school: :physical, family_flags_0: 4}
      context = SpellThreat.put_context(context, physical, SpellThreat.projection(caster))
      assert_in_delta SpellThreat.multiplier(context, true), 0.7, 0.0001
    end

    test "keeps family masks separate and supports high bits", %{target: target} do
      holder = modifiers()
      [general, critical, family] = holder.auras
      holder = %{holder | auras: [general, critical, %{family | class_mask: Bitwise.bsl(1, 33)}]}
      caster = %{target | unit: %{target.unit | auras: [holder]}}
      projection = SpellThreat.projection(caster)

      for {family, flags, expected} <- [{5, 2, 0.525}, {6, 2, 0.7}, {5, 0, 0.7}] do
        spell = %Spell{school: :shadow, spell_family: family, family_flags_1: flags}
        context = SpellThreat.put_context(%CastContext{}, spell, projection)
        assert_in_delta context.threat_multiplier, expected, 0.0001
      end
    end
  end

  describe "apply_damage_amount/6" do
    test "critical spell threat follows actual damage and database coefficients", %{target: target} do
      spell = %Spell{id: 10, school: :shadow, dmg_class: 1}

      context = %CastContext{
        caster_guid: 1,
        caster_level: 60,
        spell_crit_chance: 100,
        threat_multiplier: 0.7,
        critical_threat_multiplier: 0.75,
        spell_threat: %{multiplier: 2.0}
      }

      {target, [%Effects.SpellDamage{crit?: true, damage: damage}]} =
        DamageHeal.apply_damage_amount(target, context, spell, 100, 0)

      assert_in_delta target.internal.threat[1], damage * 0.7 * 0.75 * 2, 0.0001
      assert target.unit.health == 1_000 - damage
    end
  end

  describe "take_damage_with_mitigation/4" do
    test "absorbed damage contributes no threat", %{target: target} do
      for {shield, expected} <- [{40, 30.0}, {100, 0.0}] do
        holder = %Holder{
          spell: %Spell{id: 20},
          auras: [%Aura{type: :school_absorb, amount: shield, misc_value: 127}]
        }

        shielded = %{target | unit: %{target.unit | auras: [holder]}}
        {hit, 100, ^shield} = Core.take_damage_with_mitigation(shielded, 100, 0, source: 1, threat_multiplier: 0.5)
        assert hit.internal.threat[1] == expected
      end
    end
  end

  describe "apply/5" do
    test "critical heals scale effective healing without critical-damage threat reduction", %{target: target} do
      effect = %Effect{type: :heal, base_points: 100}
      spell = %Spell{id: 30, school: :holy, dmg_class: 1, effects: [effect]}
      target = %{target | unit: %{target.unit | health: 1_900}}

      context = %CastContext{
        caster_guid: 1,
        spell_crit_chance: 100,
        threat_multiplier: 0.7,
        critical_threat_multiplier: 0.1,
        spell_threat: %{multiplier: 2.0}
      }

      {healed, events} = DamageHeal.apply(target, context, spell, effect, 0)
      assert healed.unit.health == 2_000
      assert Enum.any?(events, &match?(%Effects.SpellHeal{crit?: true, damage: 150}, &1))
      assert [%Effects.HealThreat{amount: 70.0}] = Enum.filter(events, &match?(%Effects.HealThreat{}, &1))

      {_full, events} = DamageHeal.apply(healed, context, spell, effect, 0)
      refute Enum.any?(events, &match?(%Effects.HealThreat{}, &1))
    end
  end

  describe "heal_events/5" do
    test "Paladin direct healing has its own base ratio", %{target: target} do
      caster = %{target | unit: %{target.unit | class: 2}}
      spell = %Spell{school: :holy}
      context = SpellThreat.put_context(%CastContext{caster_guid: 1}, spell, SpellThreat.projection(caster))
      assert [%Effects.HealThreat{amount: 25.0}] = SpellThreat.heal_events(target, context, spell, 100)

      assert [%Effects.HealThreat{amount: 50.0}] =
               SpellThreat.heal_events(target, context, spell, 100, periodic?: true)
    end

    test "helpful-threat suppression excludes heals and resource assistance", %{target: target} do
      spell = %Spell{attributes: MapSet.new([:no_helpful_threat])}
      context = %CastContext{caster_guid: 1}
      assert SpellThreat.heal_events(target, context, spell, 100) == []
      assert SpellThreat.assist_events(target, context, spell, 100) == []
    end
  end

  describe "tick/3" do
    test "periodic damage and healing use supplied current contexts", %{target: target} do
      for {aura, expected_health} <- [{:periodic_damage, 900}, {:periodic_heal, 1_100}] do
        spell = periodic_spell(aura)
        {affected, _events} = AuraLogic.apply_spell(target, 1, 60, spell, 0)
        context = %CastContext{caster_guid: 1, threat_multiplier: 0.7, spell_threat: %{multiplier: 2.0}}
        {ticked, events} = AuraLogic.tick(affected, 1_000, %{{spell.id, 1, nil} => context})
        assert ticked.unit.health == expected_health
        assert hd(ticked.unit.auras).cast_context == nil

        if aura == :periodic_damage do
          assert_in_delta ticked.internal.threat[1], 140.0, 0.0001
        else
          assert [%Effects.HealThreat{amount: 70.0}] = Enum.filter(events, &match?(%Effects.HealThreat{}, &1))
        end
      end
    end

    test "mana regeneration stays threat-free while actual rage gains generate threat", %{target: target} do
      target = %{target | unit: %{target.unit | power1: 95, max_power1: 100, power2: 95, max_power2: 100}}

      for {power_type, expected} <- [{0, []}, {1, [1.25]}] do
        spell = periodic_spell(:periodic_energize)
        [effect] = spell.effects
        spell = %{spell | effects: [%{effect | misc_value: power_type}]}
        {affected, _events} = AuraLogic.apply_spell(target, 1, 60, spell, 0)
        context = %CastContext{caster_guid: 1, threat_multiplier: 0.5}
        {_ticked, events} = AuraLogic.tick(affected, 1_000, %{{spell.id, 1, nil} => context})
        assert for(%Effects.HealThreat{amount: amount} <- events, do: amount) == expected
      end
    end
  end

  defp modifiers do
    %Holder{
      spell: %Spell{id: 5, spell_family: 5},
      auras: [
        %Aura{type: :mod_threat, misc_value: 127, amount: -30},
        %Aura{type: :mod_critical_threat, misc_value: 126, amount: -25},
        %Aura{type: :add_pct_modifier, misc_value: 2, amount: -25, class_mask: 2}
      ]
    }
  end

  defp periodic_spell(aura) do
    %Spell{
      id: 40,
      school: :physical,
      duration_ms: 5_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: aura, base_points: 100, amplitude_ms: 1_000}]
    }
  end

  defp target(_context) do
    %{
      target: %Mob{
        object: %Object{guid: 2},
        unit: %Unit{health: 1_000, max_health: 2_000, level: 60, auras: []},
        internal: %Internal{world: WorldRef.open(0), in_combat: true, threat: %{1 => 0.0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end
end
