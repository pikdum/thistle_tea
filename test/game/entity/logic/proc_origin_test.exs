defmodule ThistleTea.Game.Entity.Logic.ProcOriginTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellEffect.DamageHeal
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule

  setup [:combatants]

  describe "receive/4" do
    test "aura damage cannot consume either combatant's charges or start cooldowns", %{caster: caster, target: target} do
      spell = damage_spell()
      context = aura_context()
      {target, events} = SpellEffect.receive(target, context, spell, 1_000)
      assert target.unit.health == 90
      assert [%Effects.SpellDamage{proc_origin: :suppressed} = damage] = events
      assert hd(target.unit.auras).charges == 3
      assert hd(target.unit.auras).next_proc_at == nil
      caster = damage_feedback(caster, damage)
      assert caster.internal.events == []
      assert hd(caster.unit.auras).charges == 3
      assert hd(caster.unit.auras).next_proc_at == nil
    end

    test "ordinary and exempt casts consume both sides' charges", %{caster: caster, target: target} do
      for {spell, context} <- [
            {damage_spell(), %CastContext{caster_guid: 1, caster_level: 60}},
            {%{damage_spell() | attributes: MapSet.new([:not_a_proc])}, aura_context()}
          ] do
        {hit, events} = SpellEffect.receive(target, context, spell, 1_000)
        assert hd(hit.unit.auras).charges == 2
        assert hd(hit.unit.auras).next_proc_at == 4_000
        assert Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
        damage = Enum.find(events, &is_struct(&1, Effects.SpellDamage))
        caster = damage_feedback(caster, damage)
        assert hd(caster.unit.auras).charges == 2
        assert Enum.any?(caster.internal.events, &is_struct(&1, Effects.TriggerSpell))
      end
    end

    test "item healing is suppressed even when its spell has NOT_A_PROC", %{caster: caster, target: target} do
      spell = %Spell{id: 10, effects: [%Effect{type: :heal, base_points: 10}], attributes: MapSet.new([:not_a_proc])}
      context = %CastContext{caster_guid: 1, caster_level: 60, cast_item_guid: 20}
      target = %{target | unit: %{target.unit | health: 50}}
      {target, events} = SpellEffect.receive(target, context, spell, 1_000)
      assert target.unit.health == 60
      heal = Enum.find(events, &is_struct(&1, Effects.SpellHeal))
      assert heal.proc_origin == :suppressed
      caster = damage_feedback(caster, heal)
      assert hd(caster.unit.auras).charges == 3
      assert caster.internal.events == []
    end

    test "periodic damage does not inherit the applying aura cast's suppression", %{caster: caster, target: target} do
      {target, events} =
        DamageHeal.apply_damage_amount(target, aura_context(), damage_spell(), 10, 1_000, periodic?: true)

      assert target.unit.health == 90
      assert [%Effects.SpellDamage{proc_origin: :cast, proc_type: :deal_harmful_periodic} = damage] = events
      caster = damage_feedback(caster, damage)
      assert hd(caster.unit.auras).charges == 2
    end

    test "a periodic heal applied by an item retains normal tick eligibility", %{caster: caster} do
      spell = %Spell{
        id: 20,
        duration_ms: 6_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :periodic_heal, base_points: 10, amplitude_ms: 3_000}]
      }

      context = %{aura_context() | caster_guid: 2, cast_item_guid: 30}
      target = %{caster | object: %Object{guid: 2}, unit: %{caster.unit | health: 50, auras: []}}
      {target, _} = SpellEffect.receive(target, context, spell, 0)
      {_target, events} = AuraLogic.tick(target, 3_000)
      assert Enum.any?(events, &match?(%Effects.SpellHeal{proc_origin: :cast, periodic?: true}, &1))
    end

    test "resisted aura spells cannot spend defensive charges", %{target: target} do
      holder = hd(target.unit.auras)
      holder = %{holder | spell: %{holder.spell | proc_rule: %ProcRule{proc_ex: 8}}}
      target = %{target | unit: %{target.unit | auras: [holder]}}
      context = %{aura_context() | hit_outcome: :resist}
      {result, events} = SpellEffect.receive(target, context, damage_spell(), 1_000)
      assert [%Effects.SpellLogMiss{reason: :resist}] = events
      assert hd(result.unit.auras).charges == 3

      {result, _} =
        SpellEffect.receive(target, %{context | triggered?: false, triggered_by_aura?: false}, damage_spell(), 1_000)

      assert hd(result.unit.auras).charges == 2
    end

    test "weapon ability feedback retains the origin restriction", %{caster: caster} do
      payload = %{outcome: :normal, victim_guid: 2, damage: 10, spell_id: 10, proc_origin: :suppressed}
      result = AttackFeedback.receive(caster, payload, damage_spell(), 1_000)
      assert hd(result.unit.auras).charges == 3
      assert result.internal.events == []
      result = AttackFeedback.receive(caster, %{payload | proc_origin: :cast}, damage_spell(), 1_000)
      assert hd(result.unit.auras).charges == 2
    end
  end

  defp damage_feedback(caster, damage) do
    payload = %{
      victim_guid: 2,
      outcome: :normal,
      damage: damage.damage,
      proc_type: damage.proc_type,
      proc_origin: damage.proc_origin
    }

    SpellFeedback.receive(caster, payload, damage.spell, 1_000)
  end

  defp aura_context, do: %CastContext{caster_guid: 1, caster_level: 60, triggered?: true, triggered_by_aura?: true}

  defp damage_spell,
    do: %Spell{id: 10, school: :physical, dmg_class: 1, effects: [%Effect{type: :school_damage, base_points: 10}]}

  defp combatants(_context) do
    holder = %Holder{
      spell: %Spell{id: 100, proc_type_mask: 0x74010, proc_chance: 100, proc_rule: %ProcRule{cooldown_ms: 3_000}},
      caster_guid: 1,
      caster_level: 60,
      charges: 3,
      auras: [%Aura{type: :proc_trigger_spell, trigger_spell_id: 101}]
    }

    caster = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 100, max_health: 100, auras: [holder]},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{caster: caster, target: %{caster | object: %Object{guid: 2}}}
  end
end
