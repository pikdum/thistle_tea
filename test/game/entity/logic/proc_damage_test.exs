defmodule ThistleTea.Game.Entity.Logic.ProcDamageTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.ProcDamage
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.Spell.Semantics

  setup [:entities]

  describe "reactions/3" do
    test "outgoing damage procs fire on attacks rather than retaliating", %{carrier: carrier} do
      carrier = with_proc(carrier, %{proc_spell() | proc_type_mask: 0x14})
      {updated, events} = Aura.reactions(carrier, :melee_hit_dealt, melee_context(:normal, 1_000))
      assert [%Effects.ProcDamage{target_guid: 2, effect_index: 1}] = events
      assert hd(updated.unit.auras).charges == 2

      for outcome <- [:miss, :dodge, :parry, :block] do
        {unchanged, []} = Aura.reactions(carrier, :melee_hit_dealt, melee_context(outcome, 1_000))
        assert unchanged == carrier
      end

      {unchanged, []} = Aura.reactions(carrier, :hit_taken, incoming_context(:normal, 1_000))
      assert unchanged == carrier
    end

    test "incoming damage procs honor chance, charges and cooldown", %{carrier: carrier} do
      spell = %{proc_spell() | proc_rule: %ProcRule{cooldown_ms: 1_000}}
      inactive = with_proc(carrier, %{spell | proc_chance: 0})
      assert {^inactive, []} = Aura.reactions(inactive, :hit_taken, incoming_context(:normal, 1_000))

      active = with_proc(carrier, spell)
      {active, [_]} = Aura.reactions(active, :hit_taken, incoming_context(:normal, 1_000))
      assert hd(active.unit.auras).charges == 2
      assert {^active, []} = Aura.reactions(active, :hit_taken, incoming_context(:normal, 1_999))
      {active, [_]} = Aura.reactions(active, :hit_taken, incoming_context(:crit, 2_000))
      assert hd(active.unit.auras).charges == 1
      {active, [_]} = Aura.reactions(active, :hit_taken, incoming_context(:normal, 3_000))
      assert active.unit.auras == []
    end

    test "block-only procs fire on full blocks and ignore ordinary hits", %{carrier: carrier} do
      carrier = with_proc(carrier, %{proc_spell() | proc_rule: %ProcRule{proc_ex: 0x40}})
      assert {^carrier, []} = Aura.reactions(carrier, :hit_taken, incoming_context(:normal, 1_000))
      context = Map.merge(incoming_context(:block, 1_000), %{damage: 0, absorbed: 0, proc_ex: 0x40})
      {updated, [%Effects.ProcDamage{}]} = Aura.reactions(carrier, :hit_taken, context)
      assert hd(updated.unit.auras).charges == 2
    end

    test "spell-hit procs use the same direct-damage request", %{carrier: carrier} do
      carrier = with_proc(carrier, %{proc_spell() | proc_type_mask: 0x30000})
      context = %{spell: %Spell{id: 133}, outcome: :normal, now: 1_000}

      for {event, specific} <- [
            {:spell_hit_taken, %{attacker_guid: 2, proc_type: :take_harmful_spell}},
            {:spell_hit_dealt, %{victim_guid: 2, proc_type: :deal_harmful_spell}}
          ] do
        {updated, [%Effects.ProcDamage{target_guid: 2}]} = Aura.reactions(carrier, event, Map.merge(context, specific))
        assert hd(updated.unit.auras).charges == 2
      end
    end

    test "expiry, cancellation and death prevent further procs", %{carrier: carrier} do
      {carrier, _} = Aura.apply_spell(carrier, 1, 60, proc_spell(), 0)
      {expired, _} = Aura.tick(carrier, 10_000)
      {cancelled, _} = Aura.cancel_spell(carrier, proc_spell().id, 1_000)
      dead = Core.take_damage(carrier, 1_000, 1_000)

      for ended <- [expired, cancelled, dead] do
        assert ended.unit.auras == []
        assert {^ended, []} = Aura.reactions(ended, :hit_taken, incoming_context(:normal, 10_001))
      end
    end
  end

  describe "prepare/4" do
    test "uses the carrier, original effect dice and current spell power", %{carrier: carrier, target: target} do
      spell = proc_spell()
      carrier = with_proc(carrier, spell)
      {damage_spell, context} = ProcDamage.prepare(carrier, spell, 1, 2)
      assert context.caster_guid == 1
      assert context.caster_level == 60
      assert context.spell_damage_bonus.holy == 100
      assert context.proc_damage?
      assert [%Effect{index: 1, type: :school_damage, base_points: 49, die_sides: 1}] = damage_spell.effects
      {damaged, events} = SpellEffect.receive(target, context, damage_spell, 1_000)
      assert damaged.unit.health == 900
      assert [%Effects.SpellDamage{source_guid: 1, damage: 100, crit?: false, proc_type: nil}] = events
      assert damaged.unit.auras == []
    end

    test "damage cannot reflect or trigger another incoming proc", %{carrier: carrier, target: target} do
      target = with_proc(target, %{proc_spell() | id: 90_021, proc_type_mask: 0x20000})
      reflection = %Holder{spell: %Spell{id: 90_022}, auras: [%AuraData{type: :reflect_spells, amount: 100}]}
      target = %{target | unit: %{target.unit | auras: [reflection | target.unit.auras]}}
      {spell, context} = ProcDamage.prepare(carrier, proc_spell(), 1, 2)
      {damaged, events} = SpellEffect.receive(target, context, spell, 1_000)
      assert damaged.unit.health == 900
      assert [%Effects.SpellDamage{proc_type: nil}] = events
      assert Enum.find(damaged.unit.auras, &(&1.spell.id == 90_021)).charges == 3
      refute Enum.any?(events, &is_struct(&1, Effects.DeliverSpell))
    end

    test "absorption and immunity apply without restarting a proc chain", %{carrier: carrier, target: target} do
      {spell, context} = ProcDamage.prepare(carrier, proc_spell(), 1, 2)
      shield = %Holder{spell: %Spell{id: 90_023}, auras: [%AuraData{type: :school_absorb, amount: 30, misc_value: 2}]}
      target = %{target | unit: %{target.unit | auras: [shield]}}
      {damaged, events} = SpellEffect.receive(target, context, spell, 1_000)
      assert damaged.unit.health == 930
      assert [%Effects.SpellDamage{damage: 100, absorbed: 30, proc_type: nil}] = events

      immunity = %{shield | auras: [%AuraData{type: :school_immunity, amount: 1, misc_value: 2}]}
      immune = %{target | unit: %{target.unit | auras: [immunity]}}
      assert {^immune, [%Effects.SpellLogMiss{reason: :immune}]} = SpellEffect.receive(immune, context, spell, 1_000)
      corpse = %{target | unit: %{target.unit | health: 0}}
      assert {^corpse, []} = SpellEffect.receive(corpse, context, spell, 1_000)
    end
  end

  describe "hit?/5" do
    test "hostile magic procs can miss while beneficial carrier auras cannot", %{carrier: carrier} do
      spell = proc_spell()
      assert ProcDamage.hit?(carrier, spell, %{level: 60}, false, roll: 9_999)
      hostile = %{spell | effects: [%{Enum.at(spell.effects, 1) | implicit_target_a: :target_enemy}]}
      refute ProcDamage.hit?(carrier, hostile, %{level: 60}, false, roll: 9_999)
      assert ProcDamage.hit?(carrier, hostile, %{level: 60}, false, roll: 0)
    end
  end

  defp entities(_context) do
    unit = %Unit{
      health: 1_000,
      max_health: 1_000,
      level: 60,
      class: 2,
      auras: [],
      equipment_bonuses: %{spell_holy: 100}
    }

    movement = %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}

    %{
      carrier: %Character{
        object: %Object{guid: 1},
        unit: unit,
        player: %Player{},
        internal: %Internal{},
        movement_block: movement
      },
      target: %Mob{object: %Object{guid: 2}, unit: unit, internal: %Internal{}, movement_block: movement}
    }
  end

  defp proc_spell do
    Semantics.compile(%Spell{
      id: 90_020,
      school: :holy,
      dmg_class: 1,
      duration_ms: 10_000,
      proc_type_mask: 0x28,
      proc_chance: 100,
      proc_charges: 3,
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :mod_block_percent, base_points: 30},
        %Effect{
          index: 1,
          type: :apply_aura,
          aura: :proc_trigger_damage,
          base_points: 49,
          base_dice: 1,
          die_sides: 1,
          bonus_coefficient: 0.5,
          implicit_target_a: :caster
        }
      ]
    })
  end

  defp with_proc(entity, spell) do
    holder = %Holder{
      spell: spell,
      caster_guid: 7,
      caster_level: 10,
      charges: 3,
      auras: [%AuraData{index: 1, type: :proc_trigger_damage, amount: 999}]
    }

    %{entity | unit: %{entity.unit | auras: [holder]}}
  end

  defp melee_context(outcome, now), do: %{victim_guid: 2, proc_type: :deal_melee_swing, outcome: outcome, now: now}

  defp incoming_context(outcome, now), do: %{attacker_guid: 2, proc_type: :take_melee_swing, outcome: outcome, now: now}
end
