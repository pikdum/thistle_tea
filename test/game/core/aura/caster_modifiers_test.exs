defmodule ThistleTea.Game.Core.Aura.CasterModifiersTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Test.Unique

  setup [:target]

  describe "receive/4" do
    test "bypasses caster damage bonuses and criticals while retaining target bonuses and shields", %{target: target} do
      target =
        target
        |> with_aura(:mod_damage_taken, 40)
        |> with_aura(:mod_damage_percent_taken, 50)
        |> with_aura(:school_absorb, 50)

      for class <- [0, 1, 2, 3], effect <- [:school_damage, :health_leech] do
        spell = spell(effect, class)
        {damaged, events} = SpellEffect.receive(target, context(), spell, 0)
        assert [%Effects.SpellDamage{damage: 180, absorbed: 50, crit?: false}] = damage_events(events)
        assert damaged.unit.health == 870

        if effect == :health_leech do
          assert Enum.any?(events, &match?(%Effects.HealEntity{amount: 130}, &1))
        end
      end
    end

    test "weapon groups retain base weapon damage without extra caster bonuses", %{target: target} do
      for class <- [2, 3] do
        spell = spell(:weapon_damage, class)
        context = %{context() | weapon_base_min: 100, weapon_base_max: 100, attack_time_ms: 2_000}
        {damaged, events} = SpellEffect.receive(target, context, spell, 0)
        assert [%Effects.SpellDamage{damage: 200, crit?: false, proc_damage: 200}] = damage_events(events)
        assert damaged.unit.health == 800

        if class == 2 do
          assert [%Effects.AttackOutcome{outcome: :normal, damage: 200}] =
                   Enum.filter(events, &is_struct(&1, Effects.AttackOutcome))
        end
      end
    end

    test "power drains and burns retain their base resource conversion", %{target: target} do
      for type <- [:power_burn, :power_drain] do
        spell = spell(type)
        {damaged, events} = SpellEffect.receive(target, context(), spell, 0)
        assert damaged.unit.power1 == 400

        if type == :power_burn do
          assert [%Effects.SpellDamage{damage: 100, crit?: false}] = damage_events(events)
          assert damaged.unit.health == 900
        else
          assert damaged.unit.health == 1_000
        end
      end
    end

    test "healing retains recipient modifiers and its ordinary critical rule", %{target: target} do
      target = target |> with_aura(:mod_healing, 40) |> with_aura(:mod_healing_pct, 50)
      target = %{target | unit: %{target.unit | health: 100}}

      for {chance, expected} <- [{0, 180}, {100, 270}] do
        context = %{context() | spell_crit_chance: chance}
        {healed, events} = SpellEffect.receive(target, context, spell(:heal), 0)
        assert healed.unit.health == 100 + expected
        assert [%Effects.SpellHeal{damage: ^expected}] = Enum.filter(events, &is_struct(&1, Effects.SpellHeal))
      end
    end
  end

  describe "tick/2" do
    test "periodic snapshots bypass caster bonuses and retain live target modifiers", %{target: target} do
      for type <- [:periodic_damage, :periodic_leech, :periodic_health_funnel, :periodic_heal] do
        spell = periodic_spell(type)
        {affected, _events} = Aura.apply_spell(target, context(), spell, 0)
        assert hd(hd(affected.unit.auras).auras).amount == 100
        incoming_type = if type == :periodic_heal, do: :mod_healing, else: :mod_damage_taken
        affected = with_aura(affected, incoming_type, 40)
        affected = %{affected | unit: %{affected.unit | health: 500}}
        {ticked, events} = Aura.tick(affected, 1_000)

        if type == :periodic_heal do
          assert ticked.unit.health == 620
        else
          assert ticked.unit.health == 380
          assert [%Effects.SpellDamage{damage: 120}] = damage_events(events)

          if type != :periodic_damage do
            assert Enum.any?(events, &match?(%Effects.HealEntity{amount: 120}, &1))
          end
        end

        {removed, _events} = Aura.remove_spells(ticked, [spell.id], 1_500)
        assert {^removed, []} = Aura.tick(removed, 2_000)
      end
    end

    test "periodic power burns retain resource consumption without caster damage amplification", %{target: target} do
      spell = periodic_spell(:periodic_power_burn)
      {affected, _events} = Aura.apply_spell(target, context(), spell, 0)
      {ticked, events} = Aura.tick(affected, 1_000)
      assert ticked.unit.power1 == 400
      assert ticked.unit.health == 900
      assert [%Effects.SpellDamage{damage: 100, crit?: false}] = damage_events(events)
    end
  end

  defp target(_context) do
    %{
      target: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          level: 60,
          flags: 0x00040000,
          health: 1_000,
          max_health: 1_000,
          power_type: 0,
          power1: 500,
          max_power1: 500,
          auras: []
        },
        internal: %Internal{}
      }
    }
  end

  defp context do
    %CastContext{
      caster_guid: 2,
      caster_level: 60,
      spell_crit_chance: 100,
      melee_crit_chance: 100,
      hit_chance_bonus: 100,
      spell_damage_bonus: %{fire: 100},
      healing_bonus: 100,
      spell_modifiers: [
        %Aura{type: :add_pct_modifier, misc_value: 0, amount: 100},
        %Aura{type: :add_pct_modifier, misc_value: 8, amount: 100},
        %Aura{type: :add_pct_modifier, misc_value: 22, amount: 100}
      ],
      healing_done_multiplier: 2.0,
      damage_done_multiplier: 2.0,
      happiness_multiplier: 1.25,
      damage_done_versus: [{64, 50}],
      spell_damage_versus: [{64, 100}],
      target_damage: [{64, 100}],
      target_attack_power: %{melee: [{64, 140}], ranged: [{64, 140}]},
      crit_damage_versus: [{64, 100}]
    }
  end

  defp spell(type, class \\ 1) do
    %Spell{
      id: 90_001,
      school: :fire,
      dmg_class: class,
      duration_ms: 3_000,
      attributes: MapSet.new([:ignore_caster_modifiers]),
      effects: [
        %Effect{index: 0, type: type, base_points: 100, bonus_coefficient: 0.5, misc_value: 0, multiple_value: 1.0}
      ]
    }
  end

  defp periodic_spell(type) do
    spell = spell(:apply_aura)
    %{spell | effects: [%{hd(spell.effects) | aura: type, amplitude_ms: 1_000}]}
  end

  defp with_aura(target, type, amount) do
    holder = %Holder{
      spell: %Spell{id: Unique.integer()},
      auras: [%Aura{type: type, amount: amount, misc_value: 4}]
    }

    %{target | unit: %{target.unit | auras: [holder | target.unit.auras]}}
  end

  defp damage_events(events), do: Enum.filter(events, &is_struct(&1, Effects.SpellDamage))
end
