defmodule ThistleTea.Game.Entity.Logic.TargetAttackPowerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.TargetAttackPower
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:entities]

  describe "bonus/3" do
    test "matches every bit, sums stacks, and separates melee and ranged", %{attacker: attacker, target: target} do
      attacker =
        with_auras(attacker, [
          holder(:mod_melee_attack_power_versus, 70, 36, 2),
          holder(:mod_ranged_attack_power_versus, 42, 32)
        ])

      snapshot = TargetAttackPower.snapshot(attacker)
      assert TargetAttackPower.bonus(target, snapshot, :melee) == 140
      assert TargetAttackPower.bonus(with_type(target, 3), snapshot, :melee) == 140
      assert TargetAttackPower.bonus(with_type(target, 1), snapshot, :melee) == 0
      assert TargetAttackPower.bonus(target, snapshot, :ranged) == 42
      assert TargetAttackPower.bonus(with_type(target, 3), snapshot, :ranged) == 0
      assert attacker.unit.attack_power == 140
    end

    test "adds live target debuffs and treats players as humanoids", %{attacker: attacker, target: target} do
      attacker = with_auras(attacker, [holder(:mod_melee_attack_power_versus, 70, 64)])
      snapshot = TargetAttackPower.snapshot(attacker)
      assert TargetAttackPower.bonus(attacker, snapshot, :melee) == 70
      cat = %{attacker | unit: %{attacker.unit | shapeshift_form: 1}}
      assert TargetAttackPower.bonus(cat, snapshot, :melee) == 0
      assert TargetAttackPower.bonus(cat, %{melee: [{1, 42}]}, :melee) == 42

      target =
        with_auras(target, [
          holder(:melee_attack_power_attacker_bonus, 28),
          holder(:ranged_attack_power_attacker_bonus, 42)
        ])

      assert TargetAttackPower.bonus(target, snapshot, :melee) == 28
      assert TargetAttackPower.bonus(target, snapshot, :ranged) == 42
      assert TargetAttackPower.bonus(with_auras(target, []), snapshot, :ranged) == 0
    end
  end

  describe "resolve/4" do
    test "uses actual mob types for damage and critical multipliers", %{target: target} do
      attack = %{caster_level: 60, crit_chance: 100, damage_done_versus: [{32, 10}], crit_damage_versus: [{32, 100}]}
      assert AttackTable.resolve(target, attack, 100, roll: 9_999).damage == 330
      assert AttackTable.resolve(with_type(target, 1), attack, 100, roll: 9_999).damage == 200
    end

    test "adds weapon-speed damage before armor and critical hits", %{attacker: attacker, target: target} do
      attacker = with_auras(attacker, [holder(:mod_melee_attack_power_versus, 140, 32)])
      attack = AttackTable.attacker_context(attacker)
      assert AttackTable.resolve(target, attack, 100, roll: 9_999).damage == 120
      assert AttackTable.resolve(with_type(target, 1), attack, 100, roll: 9_999).damage == 100
      armored = %{target | unit: %{target.unit | normal_resistance: 3_000}}

      assert AttackTable.resolve(armored, attack, 100, roll: 9_999).damage ==
               AttackTable.armor_reduced_damage(120, 3_000, 60)

      critical = Map.put(attack, :crit_chance, 100)
      assert AttackTable.resolve(target, critical, 100, roll: 9_999).damage == 240
      assert AttackTable.resolve(target, attack, 100, roll: 0).damage == 0
    end

    test "uses offhand speed, penalty, and damage modifiers without haste", %{attacker: attacker, target: target} do
      attacker =
        with_auras(attacker, [
          holder(:mod_melee_attack_power_versus, 140, 32),
          holder(:mod_offhand_damage_pct, 50),
          holder(:mod_damage_percent_done, 100, 1),
          holder(:mod_melee_haste, 100)
        ])

      attack = attacker |> AttackTable.attacker_context() |> Map.put(:offhand?, true)
      assert AttackTable.resolve(target, attack, 100, roll: 9_999).damage == 121
      assert AttackTable.resolve(target, Map.put(attack, :offhand?, false), 100, roll: 9_999).damage == 140
    end
  end

  describe "receive/4" do
    test "uses actual mob types for magic damage and critical multipliers", %{attacker: attacker, target: target} do
      spell = %Spell{
        id: 90_005,
        school: :holy,
        dmg_class: 1,
        effects: [%Effect{type: :school_damage, base_points: 100}]
      }

      context = %{
        context(attacker, spell)
        | spell_crit_chance: 100,
          damage_done_versus: [{32, 10}],
          crit_damage_versus: [{32, 100}]
      }

      {_target, events} = SpellEffect.receive(target, context, spell, 0)
      assert damage(events) == 220
      {_target, events} = SpellEffect.receive(with_type(target, 1), context, spell, 0)
      assert damage(events) == 150
    end

    test "normalizes bonus speed after weapon percentage and before critical damage", %{
      attacker: attacker,
      target: target
    } do
      spell = weapon_spell(:normalized_weapon_damage, 2)
      spell = %{spell | effects: spell.effects ++ [%Effect{index: 1, type: :weapon_percent_damage, base_points: 150}]}
      attacker = with_auras(attacker, [holder(:mod_melee_attack_power_versus, 140, 32)])
      context = context(attacker, spell)
      {damaged, events} = SpellEffect.receive(target, context, spell, 0)
      assert damage(events) == 50
      assert damaged.unit.health == 950
      assert context.attack_power == 140
      assert context.normalized_speed == 2.0
      {_target, events} = SpellEffect.receive(target, %{context | melee_crit_chance: 100}, spell, 0)
      assert damage(events) == 100
    end

    test "combines ranged creature bonuses and Hunter's Mark once", %{attacker: attacker, target: target} do
      spell = weapon_spell(:weapon_damage, 3)

      attacker =
        with_auras(attacker, [
          holder(:mod_melee_attack_power_versus, 999, 32),
          holder(:mod_ranged_attack_power_versus, 140, 32)
        ])

      target = with_auras(target, [holder(:ranged_attack_power_attacker_bonus, 70)])
      context = context(attacker, spell)
      {_target, events} = SpellEffect.receive(target, context, spell, 0)
      assert damage(events) == 70
      {_target, events} = SpellEffect.receive(with_auras(target, []), context, spell, 0)
      assert damage(events) == 56
      {_target, events} = SpellEffect.receive(with_type(target, 1), context, spell, 0)
      assert damage(events) == 42
    end

    test "does not add weapon-speed bonuses to flat melee abilities", %{attacker: attacker, target: target} do
      spell = weapon_spell(:school_damage, 2)
      spell = %{spell | effects: [%Effect{type: :school_damage, base_points: 100}]}
      attacker = with_auras(attacker, [holder(:mod_melee_attack_power_versus, 1_400, 32)])
      {_target, events} = SpellEffect.receive(target, context(attacker, spell), spell, 0)
      assert damage(events) == 100
    end
  end

  describe "apply_spell/5" do
    test "new attacks reflect cancellation, expiry, and death", %{attacker: attacker, target: target} do
      spell = %Spell{
        id: 90_001,
        duration_ms: 1_000,
        effects: [%Effect{type: :apply_aura, aura: :mod_melee_attack_power_versus, base_points: 140, misc_value: 32}]
      }

      {buffed, _events} = Aura.apply_spell(attacker, 1, 60, spell, 0)
      snapshot = TargetAttackPower.snapshot(buffed)
      assert TargetAttackPower.bonus(target, snapshot, :melee) == 140
      assert buffed.unit.attack_power == attacker.unit.attack_power
      assert buffed.unit.min_damage == attacker.unit.min_damage
      {cancelled, _events} = Aura.remove_spells(buffed, [spell.id], 500)
      {expired, _events} = Aura.tick(buffed, 1_000)
      dead = Core.take_damage(buffed, 1_000, 500)

      for {reason, entity} <- [cancelled: cancelled, expired: expired, dead: dead] do
        assert TargetAttackPower.bonus(target, TargetAttackPower.snapshot(entity), :melee) == 0,
               inspect({reason, entity.unit.health, entity.unit.auras})
      end

      assert TargetAttackPower.bonus(target, snapshot, :melee) == 140
    end
  end

  defp entities(_context) do
    unit = %Unit{
      health: 1_000,
      max_health: 1_000,
      level: 60,
      class: 1,
      attack_power: 140,
      ranged_attack_power: 140,
      base_min_damage: 0,
      base_max_damage: 0,
      min_damage: 20,
      max_damage: 20,
      base_ranged_min_damage: 0,
      base_ranged_max_damage: 0,
      base_attack_time: 2_000,
      offhand_attack_time: 1_400,
      ranged_attack_time: 2_800,
      auras: []
    }

    attacker = %Character{
      object: %Object{guid: 1},
      unit: unit,
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    target = %Mob{
      object: %Object{guid: 2},
      unit: %{unit | attack_power: 0, flags: 0x00040000},
      internal: %Internal{creature: %Creature{creature_type: 6}}
    }

    %{attacker: attacker, target: target}
  end

  defp holder(type, amount, mask \\ 0, stacks \\ 1) do
    %Holder{
      spell: %Spell{id: 90_000},
      caster_guid: 1,
      stacks: stacks,
      auras: [%AuraData{type: type, amount: amount, misc_value: mask}]
    }
  end

  defp with_auras(entity, holders), do: %{entity | unit: %{entity.unit | auras: holders}}

  defp with_type(entity, type),
    do: %{entity | internal: %{entity.internal | creature: %{entity.internal.creature | creature_type: type}}}

  defp weapon_spell(type, damage_class) do
    %Spell{id: 90_002, school: :physical, dmg_class: damage_class, effects: [%Effect{type: type, base_points: 0}]}
  end

  defp context(attacker, spell) do
    %{
      CastContext.from_caster(attacker, spell, 2)
      | hit_chance_bonus: 100,
        melee_crit_chance: 0,
        spell_crit_chance: 0,
        caster_position: nil
    }
  end

  defp damage(events) do
    Enum.find_value(events, fn
      %Effects.SpellDamage{damage: damage} -> damage
      _event -> nil
    end)
  end
end
