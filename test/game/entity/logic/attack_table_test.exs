defmodule ThistleTea.Game.Entity.Logic.AttackTableTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Spell.Cast

  @warrior 1
  @mage 8

  defp mob(overrides \\ []) do
    unit = %Unit{health: 100, level: 20, strength: 40, auras: []}

    %{
      object: %Object{guid: 100},
      unit: struct(unit, Keyword.get(overrides, :unit, [])),
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{creature: struct(%Creature{}, Keyword.get(overrides, :creature, []))}
    }
  end

  defp character(overrides) do
    unit = %Unit{health: 100, level: 20, class: @warrior, agility: 20, strength: 40, auras: []}

    %Character{
      object: %Object{guid: 200},
      unit: struct(unit, Keyword.get(overrides, :unit, [])),
      player: struct(%Player{}, Keyword.get(overrides, :player, [])),
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: struct(%Internal{}, Keyword.get(overrides, :internal, []))
    }
  end

  defp attack(overrides \\ []) do
    Enum.into(overrides, %{caster: 1, caster_level: 20, caster_player?: true, crit_chance: 5.0})
  end

  describe "resolve/4 outcome roll" do
    test "low roll against an even-level mob is a miss" do
      result = AttackTable.resolve(mob(), attack(), 100, roll: 0)

      assert result.outcome == :miss
      assert result.damage == 0
      assert result.hit_info == 0x12
      assert result.victim_state == 0
    end

    test "rolls walk miss, dodge, parry, glancing, block in order against a mob" do
      # even level: miss 500, dodge 500, parry 500, glancing 1000, block 500, crit 500
      assert AttackTable.resolve(mob(), attack(), 100, roll: 499).outcome == :miss
      assert AttackTable.resolve(mob(), attack(), 100, roll: 500).outcome == :dodge
      assert AttackTable.resolve(mob(), attack(), 100, roll: 1_000).outcome == :parry
      assert AttackTable.resolve(mob(), attack(), 100, roll: 1_500).outcome == :glancing
      assert AttackTable.resolve(mob(), attack(), 100, roll: 2_500).outcome == :block
      assert AttackTable.resolve(mob(), attack(), 100, roll: 3_000).outcome == :crit
      assert AttackTable.resolve(mob(), attack(), 100, roll: 3_500).outcome == :normal
      assert AttackTable.resolve(mob(), attack(), 100, roll: 9_999).outcome == :normal
    end

    test "crits deal double damage with the crit flag" do
      result = AttackTable.resolve(mob(), attack(), 100, roll: 3_000)

      assert result.outcome == :crit
      assert result.damage == 200
      assert result.hit_info == 0x82
      assert result.victim_state == 1
    end

    test "glancing blows reduce damage" do
      result = AttackTable.resolve(mob(), attack(), 100, roll: 1_500, glance_roll: 0.0)

      assert result.outcome == :glancing
      assert result.damage == 91
      assert result.hit_info == 0x4002
    end

    test "mob blocks subtract the creature block value" do
      result = AttackTable.resolve(mob(), attack(), 100, roll: 2_500)

      # level 20 mob with 40 strength blocks 12
      assert result.outcome == :block
      assert result.damage == 88
      assert result.blocked_amount == 12
      assert result.victim_state == 1
    end

    test "creatures with the no-parry extra flag cannot parry" do
      target = mob(creature: [extra_flags: 0x4])

      assert AttackTable.resolve(target, attack(), 100, roll: 1_000).outcome == :glancing
    end

    test "creatures with the no-block extra flag cannot block" do
      target = mob(creature: [extra_flags: 0x10])

      assert AttackTable.resolve(target, attack(), 100, roll: 2_500).outcome == :crit
    end

    test "queued melee spells cannot glance" do
      result = AttackTable.resolve(mob(), attack(queued_spell_id: 78), 100, roll: 1_500)

      assert result.outcome == :block
    end

    test "mob attackers can crush players three or more levels below" do
      target = character(unit: [level: 10, class: @mage, agility: 0])
      swing = attack(caster_level: 13, caster_player?: false)

      # miss 440, dodge 260, crit 560, then crushing 1500 from 1260
      result = AttackTable.resolve(target, swing, 100, roll: 2_000)

      assert result.outcome == :crushing
      assert result.damage == 150
      assert result.hit_info == 0x8002
    end

    test "player attackers never crush" do
      target = character(unit: [level: 10, class: @mage, agility: 0])

      result = AttackTable.resolve(target, attack(caster_level: 20), 100, roll: 9_999)

      assert result.outcome == :normal
    end

    test "always-crush attackers always crush" do
      swing = attack(caster_player?: false, always_crush?: true)
      target = character(unit: [class: @mage, agility: 0])

      assert AttackTable.resolve(target, swing, 100, roll: 9_999).outcome == :crushing
    end

    test "attacks against a sitting player auto-crit and never miss" do
      target = character(unit: [stand_state: 1, class: @mage, agility: 0])

      assert AttackTable.resolve(target, attack(), 100, roll: 0).outcome == :crit
      assert AttackTable.resolve(target, attack(), 100, roll: 9_999).outcome == :crit
    end

    test "players cannot dodge, parry, or block attacks from behind" do
      # defender at origin facing +x, attacker behind at -x
      target = character(unit: [class: @warrior, agility: 1_000], player: [], internal: [])
      target = %{target | unit: %{target.unit | equipment_bonuses: %{shields: 1, shield_block: 10}}}
      swing = attack(caster_position: {-5.0, 0.0, 0.0})

      result = AttackTable.resolve(target, swing, 100, roll: 700)

      assert result.outcome in [:crit, :normal]
    end

    test "a casting defender cannot dodge, parry, or block" do
      target = character(internal: [casting: %Cast{}])

      result = AttackTable.resolve(target, attack(), 100, roll: 800)

      refute result.outcome in [:dodge, :parry, :block]
    end

    test "player blocks use the shield block value plus strength bonus" do
      target = character(unit: [class: @warrior, agility: 0, strength: 40])
      target = %{target | unit: %{target.unit | equipment_bonuses: %{shields: 1, shield_block: 20}}}

      # miss 500, no dodge at zero agility, parry 500, block 500
      result = AttackTable.resolve(target, attack(caster_player?: false), 100, roll: 1_200)

      assert result.outcome == :block
      assert result.blocked_amount == 21
      assert result.damage == 79
    end

    test "players without a shield cannot block" do
      target = character(unit: [class: @warrior, agility: 0])

      result = AttackTable.resolve(target, attack(caster_player?: false), 100, roll: 1_200)

      refute result.outcome == :block
    end
  end

  describe "armor mitigation" do
    test "reduces physical damage by the vanilla armor formula" do
      # armor 1000 vs level 20: 1000 / (1000 + 85*20 + 400) = 32.26% reduction
      target = mob(unit: [normal_resistance: 1_000])

      result = AttackTable.resolve(target, attack(), 100, roll: 9_999)

      assert result.damage == 68
    end

    test "does not reduce non-physical melee damage" do
      target = mob(unit: [normal_resistance: 1_000])

      result = AttackTable.resolve(target, attack(spell_school_mask: 0x4), 100, roll: 9_999)

      assert result.damage == 100
    end

    test "armor reduction caps at 75 percent" do
      assert AttackTable.armor_reduced_damage(100, 1_000_000, 20) == 25
    end

    test "landed hits deal at least 1 damage" do
      assert AttackTable.armor_reduced_damage(1, 5_000, 20) == 1
    end
  end
end
