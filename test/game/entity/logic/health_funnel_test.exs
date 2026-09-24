defmodule ThistleTea.Game.Entity.Logic.HealthFunnelTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Coefficient
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:target]

  describe "tick/2" do
    test "drains on schedule and expires after its final tick", %{target: target} do
      spell = spell()
      context = %CastContext{caster_guid: 2, caster_level: 60, target_hostile?: true}
      {target, _events} = AuraLogic.apply_spell(target, context, spell, 0)
      assert AuraLogic.next_event_at(target) == 1_000
      assert {^target, []} = AuraLogic.tick(target, 999)
      {target, events} = AuraLogic.tick(target, 1_000)
      assert target.unit.health == 900
      assert damage(events) == 100
      assert healing(events) == 100
      assert hd(target.unit.auras).negative?
      {target, events} = AuraLogic.tick(target, 2_000)
      assert target.unit.health == 800
      assert healing(events) == 100
      assert target.unit.auras == []
      assert AuraLogic.next_event_at(target) == nil
    end

    test "scales stacked drains and only transfers actual health lost", %{target: target} do
      for type <- [:periodic_leech, :periodic_health_funnel],
          {health, shield, damage, drained} <- [{1_000, 50, 200, 150}, {1_000, 200, 200, 0}, {20, 50, 200, 20}] do
        shield = holder(:school_absorb, shield, 1)
        target = %{target | unit: %{target.unit | health: health, auras: [shield]}}
        spell = %{spell(type, 2.0) | stack_amount: 2}
        {target, _events} = AuraLogic.apply_spell(target, 2, 60, spell, 0)
        {target, _events} = AuraLogic.apply_spell(target, 2, 60, spell, 1)
        {target, events} = AuraLogic.tick(target, 1_000)
        assert target.unit.health == health - drained
        assert damage(events) == damage
        assert healing(events) == drained * 2
        refute Enum.any?(target.unit.auras, &(&1.spell.id == shield.spell.id and hd(&1.auras).amount > 0))
      end
    end

    test "school immunity suppresses both sides of the transfer", %{target: target} do
      target = %{target | unit: %{target.unit | auras: [holder(:damage_immunity, 0, 1)]}}
      {target, _events} = AuraLogic.apply_spell(target, 2, 60, spell(), 0)
      {target, events} = AuraLogic.tick(target, 1_000)
      assert target.unit.health == 1_000
      assert [%Effects.SpellDamageImmune{spell_id: 24_617}] = events
      assert AuraLogic.next_event_at(target) == 2_000
    end

    test "applies live damage reduction before calculating healing", %{target: target} do
      {target, _events} = AuraLogic.apply_spell(target, 2, 60, spell(), 0)
      target = %{target | unit: %{target.unit | auras: [holder(:mod_damage_percent_taken, -50, 1) | target.unit.auras]}}
      {target, events} = AuraLogic.tick(target, 1_000)
      assert target.unit.health == 950
      assert healing(events) == 50
    end

    test "removed funnels cannot deal another tick", %{target: target} do
      {target, _events} = AuraLogic.apply_spell(target, 2, 60, spell(), 0)
      {target, _events} = AuraLogic.remove_spells(target, [24_617], 500)
      assert {^target, []} = AuraLogic.tick(target, 1_000)
    end

    test "self-targeted funnels return the drained health through the owner", %{target: target} do
      {target, _events} = AuraLogic.apply_spell(target, 1, 60, spell(), 0)
      {target, events} = AuraLogic.tick(target, 1_000)
      assert target.unit.health == 900
      assert Enum.any?(events, &match?(%Effects.HealEntity{target_guid: 1, amount: 100}, &1))
    end
  end

  describe "apply_spell/4" do
    test "snapshots outgoing damage percentages before the drain transfer", %{target: target} do
      for type <- [:periodic_damage, :periodic_leech, :periodic_health_funnel] do
        context = %CastContext{
          caster_guid: 2,
          caster_level: 60,
          damage_done_multiplier: 1.5,
          damage_done_versus: [{64, 20}, {1, 50}]
        }

        {affected, _events} = AuraLogic.apply_spell(target, context, spell(type, 2.0), 0)
        {ticked, events} = AuraLogic.tick(affected, 1_000)
        assert ticked.unit.health == 820
        assert damage(events) == 180
        if type != :periodic_damage, do: assert(healing(events) == 360)
        {refreshed, _events} = AuraLogic.apply_spell(ticked, 2, 60, spell(type, 2.0), 1_000)
        assert hd(hd(refreshed.unit.auras).auras).amount == 100
      end
    end

    test "outgoing damage percentages skip fixed damage and healing", %{target: target} do
      context = %CastContext{caster_guid: 2, damage_done_multiplier: 2.0, damage_done_versus: [{64, 50}]}

      for spell <- [
            %{spell() | custom_flags: 0x010},
            %{spell() | attributes: MapSet.new([:ignore_caster_modifiers])},
            %{spell(:periodic_damage) | id: 12_654},
            spell(:periodic_heal),
            spell(:periodic_mana_leech)
          ] do
        {affected, _events} = AuraLogic.apply_spell(target, context, spell, 0)
        assert hd(hd(affected.unit.auras).auras).amount == 100
      end
    end

    test "friendly health funnels retain their positive aura polarity", %{target: target} do
      spell = spell()
      spell = %{spell | effects: [%{hd(spell.effects) | implicit_target_a: :target_ally}]}
      context = %CastContext{caster_guid: 2, caster_level: 60, target_hostile?: false}
      {target, _events} = AuraLogic.apply_spell(target, context, spell, 0)
      refute hd(target.unit.auras).negative?
    end

    test "snapshots spell power and transfer modifiers independently", %{target: target} do
      effect = %{hd(spell().effects) | bonus_coefficient: 0.5}
      spell = %{spell() | effects: [effect]}

      context = %CastContext{
        caster_guid: 2,
        caster_level: 60,
        spell_damage_bonus: %{physical: 100},
        spell_modifiers: [%Aura{type: :add_pct_modifier, misc_value: 27, amount: 50}]
      }

      {target, _events} = AuraLogic.apply_spell(target, context, spell, 0)
      {target, events} = AuraLogic.tick(target, 1_000)
      assert target.unit.health == 850
      assert damage(events) == 150
      assert healing(events) == 225
    end

    test "a zero transfer modifier does not revert to the default ratio", %{target: target} do
      context = %CastContext{
        caster_guid: 2,
        caster_level: 60,
        spell_modifiers: [%Aura{type: :add_pct_modifier, misc_value: 27, amount: -100}]
      }

      {target, _events} = AuraLogic.apply_spell(target, context, spell(), 0)
      {target, events} = AuraLogic.tick(target, 1_000)
      assert target.unit.health == 900
      assert damage(events) == 100
      assert healing(events) == 0
    end
  end

  describe "value/3" do
    test "uses the vanilla fallback tick count without the leech coefficient penalty" do
      spell = %{spell() | duration_ms: 10_000, attributes: MapSet.new([:channeled])}
      assert_in_delta Coefficient.value(spell, hd(spell.effects), :dot), 1 / 3, 0.00001
    end
  end

  defp target(_context) do
    %{
      target: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{health: 1_000, max_health: 1_000, level: 60, auras: []},
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp spell(type \\ :periodic_health_funnel, multiple \\ 0.0) do
    %Spell{
      id: 24_617,
      school: :physical,
      duration_ms: 2_000,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: type,
          base_points: 100,
          amplitude_ms: 1_000,
          implicit_target_a: :target_enemy,
          multiple_value: multiple
        }
      ]
    }
  end

  defp holder(type, amount, mask) do
    %Holder{spell: %Spell{id: 9}, auras: [%Aura{type: type, amount: amount, misc_value: mask}]}
  end

  defp damage(events),
    do:
      Enum.find_value(events, 0, fn
        %Effects.SpellDamage{damage: damage} -> damage
        _event -> nil
      end)

  defp healing(events),
    do:
      Enum.find_value(events, 0, fn
        %Effects.HealEntity{amount: amount} -> amount
        _event -> nil
      end)
end
