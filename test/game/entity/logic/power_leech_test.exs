defmodule ThistleTea.Game.Entity.Logic.PowerLeechTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.PowerLeech
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:mana_users]

  describe "direct/4" do
    test "transfers only available mana and leaves health and regeneration unchanged", ctx do
      {victim, [leech]} = SpellEffect.receive(ctx.victim, ctx.context, spell(:power_drain), 100)
      assert victim.unit.power1 == 0
      assert victim.unit.health == 1_000
      assert victim.internal.last_mana_use_at == ctx.victim.internal.last_mana_use_at
      assert victim.internal.broadcast_update?
      assert %Effects.LeechPower{source_guid: 2, target_guid: 1, amount: 150, multiplier: 0.5} = leech

      {caster, [log]} = PowerLeech.restore(ctx.caster, leech)
      assert caster.unit.power1 == 75
      assert %Effects.SpellPowerDrain{amount: 150, multiplier: 0.5, power_type: 0} = log
    end

    test "self drains and non-mana drains never refund mana", ctx do
      context = %{ctx.context | caster_guid: 1}

      {victim, [%Effects.SpellPowerDrain{multiplier: +0.0}]} =
        SpellEffect.receive(ctx.victim, context, spell(:power_drain, implicit_target_a: :caster), 100)

      assert victim.unit.power1 == 0

      target = %{ctx.victim | unit: %{ctx.victim.unit | power_type: 3, power4: 60}}

      {victim, [%Effects.SpellPowerDrain{amount: 60, power_type: 3, multiplier: +0.0}]} =
        SpellEffect.receive(target, ctx.context, spell(:power_drain, misc_value: 3), 100)

      assert victim.unit.power1 == 150
      assert victim.unit.power4 == 0
    end

    test "applies direct spell bonuses, target mitigation, and conversion modifiers", ctx do
      context = %{
        ctx.context
        | spell_damage_bonus: %{shadow: 80},
          damage_done_multiplier: 1.5,
          spell_modifiers: [%AuraData{type: :add_pct_modifier, misc_value: 27, amount: 100}]
      }

      victim = with_aura(ctx.victim, :mod_damage_percent_taken, -50, 32)
      {victim, [leech]} = SpellEffect.receive(victim, context, spell(:power_drain, base_points: 40), 100)
      assert leech.amount == 60
      assert leech.multiplier == 1.0
      assert victim.unit.power1 == 90
    end

    test "direct zero conversion defaults to one", ctx do
      {_, [leech]} = SpellEffect.receive(ctx.victim, ctx.context, spell(:power_drain, multiple_value: 0.0), 100)
      assert leech.multiplier == 1.0
    end

    test "dead, immune, invalid, and inactive resource targets retain their power", ctx do
      for target <- [
            %{ctx.victim | unit: %{ctx.victim.unit | health: 0}},
            %{ctx.victim | unit: %{ctx.victim.unit | power_type: 3}},
            with_aura(ctx.victim, :school_immunity, 0, 32)
          ] do
        {victim, events} = SpellEffect.receive(target, ctx.context, spell(:power_drain), 100)
        assert victim.unit.power1 == 150
        refute Enum.any?(events, &is_struct(&1, Effects.LeechPower))
      end

      for power <- [-1, 5] do
        {victim, []} = SpellEffect.receive(ctx.victim, ctx.context, spell(:power_drain, misc_value: power), 100)
        assert victim.unit.power1 == 150
      end
    end
  end

  describe "restore/3" do
    test "caps restoration and bases periodic threat on actual gain", ctx do
      leech = leech(periodic?: true, threat_multiplier: 0.8)
      caster = %{ctx.caster | unit: %{ctx.caster.unit | power1: 140}}
      {caster, [log, threat]} = PowerLeech.restore(caster, leech)
      assert caster.unit.power1 == 150
      assert %Effects.PeriodicAuraLog{aura_type: :periodic_mana_leech, amount: 100, multiplier: 0.5} = log
      assert %Effects.AddThreat{source_guid: 2, target_guid: 1, amount: 4.0} = threat
      {^caster, [_log]} = PowerLeech.restore(caster, leech)
    end

    test "unavailable pools and dead recipients produce no gains or threat", ctx do
      for unit <- [%{ctx.caster.unit | health: 0}, %{ctx.caster.unit | max_power1: 0}] do
        caster = %{ctx.caster | unit: unit}
        {^caster, [log]} = PowerLeech.restore(caster, leech(periodic?: true))
        assert log.multiplier == 0.0
      end
    end

    test "periodic conversion zero remains zero and reads current caster modifiers", ctx do
      {caster, [log]} = PowerLeech.restore(ctx.caster, leech(periodic?: true, multiplier: 0.0))
      assert caster.unit.power1 == 0
      assert log.multiplier == 0.0
      caster = with_aura(caster, :add_pct_modifier, 100, 27)
      {caster, [log, _threat]} = PowerLeech.restore(caster, leech(periodic?: true))
      assert caster.unit.power1 == 100
      assert log.multiplier == 1.0
    end

    test "direct fractional gains dither while periodic gains truncate", ctx do
      leech = leech(amount: 3)
      assert {low, [_]} = PowerLeech.restore(ctx.caster, leech, 0.9)
      assert {high, [_]} = PowerLeech.restore(ctx.caster, leech, 0.1)
      assert {low.unit.power1, high.unit.power1} == {1, 2}
      assert {periodic, [_, _]} = PowerLeech.restore(ctx.caster, %{leech | periodic?: true}, 0.1)
      assert periodic.unit.power1 == 1
    end
  end

  describe "tick/2" do
    test "ticks remove damage-interrupted auras without restoring the removed holder", ctx do
      interrupted = %Holder{
        spell: %Spell{id: 17, aura_interrupt_flags: 2},
        caster_guid: 1,
        auras: [%AuraData{type: :dummy}],
        expires_at: -1
      }

      victim = %{ctx.victim | unit: %{ctx.victim.unit | auras: [interrupted]}}
      {victim, _} = Aura.apply_spell(victim, ctx.context, spell(:apply_aura), 100)
      {victim, events} = Aura.tick(victim, 1_100)
      assert Enum.any?(events, &is_struct(&1, Effects.LeechPower))
      refute Aura.has_spell?(victim, 17)
      assert Aura.has_spell?(victim, 5138)
      assert Aura.next_event_at(victim) == 2_100
    end

    test "drains active energy without touching mana", ctx do
      victim = %{ctx.victim | unit: %{ctx.victim.unit | power_type: 3, power4: 60}}
      {victim, _} = Aura.apply_spell(victim, ctx.context, spell(:apply_aura, misc_value: 3), 100)
      {victim, [%Effects.LeechPower{amount: 60, power_type: 3} = leech]} = Aura.tick(victim, 1_100)
      assert {victim.unit.power1, victim.unit.power4} == {150, 0}
      caster = %{ctx.caster | unit: %{ctx.caster.unit | power4: 0, max_power4: 100}}
      {caster, [log, _]} = PowerLeech.restore(caster, leech)
      assert {caster.unit.power1, caster.unit.power4} == {0, 30}
      assert log.misc_value == 3
    end

    test "missing casters and changed forms skip ticks without accumulating catch-up drains", ctx do
      context = %{ctx.context | caster_available?: false}
      {victim, _} = Aura.apply_spell(ctx.victim, context, spell(:apply_aura), 100)
      {victim, []} = Aura.tick(victim, 1_100)
      assert victim.unit.power1 == 150
      assert Aura.next_event_at(victim) == 2_100
      [holder] = victim.unit.auras
      holder = %{holder | cast_context: ctx.context}
      victim = %{victim | unit: %{victim.unit | power_type: 3, auras: [holder]}}
      {victim, []} = Aura.tick(victim, 2_100)
      assert victim.unit.power1 == 150
      victim = %{victim | unit: %{victim.unit | power_type: 0}}
      {victim, [%Effects.LeechPower{amount: 150}]} = Aura.tick(victim, 3_100)
      assert victim.unit.power1 == 0
      assert victim.unit.auras == []
    end

    test "removal and death clear scheduled transfers", ctx do
      {victim, _} = Aura.apply_spell(ctx.victim, ctx.context, spell(:apply_aura), 100)
      {removed, _} = Aura.remove_spells(victim, [5138], 500)
      dead = Core.take_damage(victim, 1_000, 500, environmental?: true)

      for target <- [removed, dead] do
        {target, []} = Aura.tick(target, 1_100)
        assert target.unit.power1 == 150
        assert Aura.next_event_at(target) == nil
      end
    end
  end

  defp mana_users(_context) do
    victim = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 1_000, max_health: 1_000, power_type: 0, power1: 150, max_power1: 150, auras: []},
      internal: %Internal{world: WorldRef.open(0)}
    }

    caster = %{victim | object: %Object{guid: 2}, unit: %{victim.unit | power1: 0}}
    %{victim: victim, caster: caster, context: %CastContext{caster_guid: 2, caster_level: 60}}
  end

  defp spell(type, opts \\ []) do
    effect =
      struct!(
        %Effect{
          index: 0,
          type: type,
          aura: if(type == :apply_aura, do: :periodic_mana_leech),
          base_points: 200,
          misc_value: 0,
          multiple_value: 0.5,
          amplitude_ms: 1_000,
          bonus_coefficient: 0.5,
          implicit_target_a: :target_enemy
        },
        opts
      )

    %Spell{
      id: 5138,
      school: :shadow,
      spell_family: 5,
      family_flags_0: 1,
      dmg_class: 1,
      duration_ms: 3_000,
      effects: [effect]
    }
  end

  defp leech(opts) do
    struct!(
      %Effects.LeechPower{
        source_guid: 2,
        target_guid: 1,
        spell: spell(:power_drain),
        power_type: 0,
        amount: 100,
        multiplier: 0.5
      },
      opts
    )
  end

  defp with_aura(entity, type, amount, misc) do
    holder = %Holder{
      spell: %Spell{id: 17, spell_family: 5},
      caster_guid: entity.object.guid,
      auras: [%AuraData{type: type, amount: amount, misc_value: misc, class_mask: 1}]
    }

    %{entity | unit: %{entity.unit | auras: [holder | entity.unit.auras]}}
  end
end
