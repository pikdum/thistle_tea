defmodule ThistleTea.Game.Entity.Logic.ElementalCombatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackSchool
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  setup [:combatants]

  describe "attacker_context/2" do
    test "retains the template school in both hand snapshots", %{attacker: attacker} do
      for hand <- [:mainhand, :offhand] do
        assert AttackTable.attacker_context(attacker, hand).spell_school_mask == 4
      end

      physical = %{attacker | internal: %Internal{}}
      assert AttackSchool.melee(physical) == :physical
      assert AttackTable.attacker_context(physical).spell_school_mask == 1
    end
  end

  describe "damage_range/1" do
    test "applies only the matching school's outgoing flat and percentage bonuses", %{attacker: attacker} do
      attacker =
        attacker
        |> aura(:mod_damage_done, 20, 4)
        |> aura(:mod_damage_percent_done, 50, 4)
        |> aura(:mod_damage_done, 100, 1)

      assert Combat.damage_range(attacker) == {180.0, 180.0}
      assert AttackTable.attacker_context(attacker).attack_damage_multipliers.mainhand == 1.5
      assert attacker.unit.min_damage == 100
      assert attacker.unit.max_damage == 100
    end
  end

  describe "receive_attack/4" do
    test "elemental swings bypass armor while physical swings still use it", %{target: target, attack: attack} do
      {elemental, events} = Combat.receive_attack(target, attack, 1_000, roll: 9_999, resist_roll: 99)
      assert elemental.unit.health == 900
      assert hit(events).attack.spell_school_mask == 4

      {physical, _events} = Combat.receive_attack(target, %{attack | spell_school_mask: 1}, 1_000, roll: 9_999)
      assert physical.unit.health > 900
      assert physical.unit.health < 1_000
    end

    test "resistance applies before the matching ward and reports both amounts", %{target: target, attack: attack} do
      target = %{target | unit: %{target.unit | fire_resistance: 250}}
      target = aura(target, :school_absorb, 10, 4)
      {damaged, events} = Combat.receive_attack(target, attack, 1_000, roll: 9_999, resist_roll: 0)
      assert damaged.unit.health == 985
      assert hit(events).damage == 15
      assert %{resist: 75, absorb: 10, hit_info: 0x62} = hit(events).attack

      assert [%Effects.AttackOutcome{outcome: :normal, damage: 15}] =
               Enum.filter(events, &is_struct(&1, Effects.AttackOutcome))
    end

    test "penetration removes school resistance without changing the target's stat", %{target: target, attack: attack} do
      target = %{target | unit: %{target.unit | fire_resistance: 250}}
      attack = %{attack | resistance_penetration: [{4, -250}]}
      {damaged, events} = Combat.receive_attack(target, attack, 1_000, roll: 9_999, resist_roll: 0)
      assert damaged.unit.health == 900
      assert damaged.unit.fire_resistance == 250
      assert hit(events).attack.resist == 0
    end

    test "unrelated wards do not absorb elemental swings", %{target: target, attack: attack} do
      target = aura(target, :school_absorb, 500, 16)
      {damaged, events} = Combat.receive_attack(target, attack, 1_000, roll: 9_999, resist_roll: 99)
      assert damaged.unit.health == 900
      assert hit(events).attack.absorb == 0
      assert [%Holder{auras: [%AuraData{amount: 500}]}] = damaged.unit.auras
    end

    test "Dampen Magic cannot reduce an elemental swing below half", %{target: target, attack: attack} do
      target = aura(target, :mod_damage_taken, -1_000, 126)
      {damaged, events} = Combat.receive_attack(target, attack, 1_000, roll: 9_999, resist_roll: 99)
      assert damaged.unit.health == 950
      assert hit(events).damage == 50

      amplified = aura(%{target | unit: %{target.unit | auras: []}}, :mod_damage_taken, 20, 4)
      {damaged, _events} = Combat.receive_attack(amplified, attack, 1_000, roll: 9_999, resist_roll: 99)
      assert damaged.unit.health == 880
    end

    test "immunity wins before resistance and absorption", %{target: target, attack: attack} do
      target = %{target | internal: %{target.internal | creature: %Creature{school_immune_mask: 4}}}
      target = aura(target, :school_absorb, 500, 4)
      {unchanged, events} = Combat.receive_attack(target, attack, 1_000, roll: 9_999, resist_roll: 0)
      assert unchanged.unit.health == 1_000
      assert unchanged.unit.auras == target.unit.auras
      assert %{resist: 0, absorb: 0, damage_state: 7} = hit(events).attack
      assert hit(events).damage == 0
    end
  end

  defp hit(events), do: Enum.find(events, &is_struct(&1, Effects.AttackerStateUpdate))

  defp aura(entity, type, amount, mask) do
    holder = %Holder{
      spell: %Spell{id: System.unique_integer([:positive])},
      auras: [%AuraData{type: type, amount: amount, misc_value: mask}]
    }

    %{entity | unit: %{entity.unit | auras: [holder | entity.unit.auras]}}
  end

  defp combatants(_context) do
    attacker = %Mob{
      object: %Object{guid: 2},
      unit: %Unit{level: 50, min_damage: 100, max_damage: 100, base_attack_time: 2_000, auras: []},
      internal: %Internal{creature: %Creature{damage_school: 2}}
    }

    target = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{health: 1_000, max_health: 1_000, level: 50, normal_resistance: 10_000, auras: []},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    attack = attacker |> AttackTable.attacker_context() |> Map.merge(%{caster: 2, damage: 100})
    %{attacker: attacker, target: target, attack: attack}
  end
end
