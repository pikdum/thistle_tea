defmodule ThistleTea.Game.Entity.Logic.AttackAccuracyTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.MeleeSpell
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast

  setup [:combatants]

  defp combatants(_context) do
    attacker = %Character{
      unit: %Unit{level: 20, class: 1, base_offhand_max_damage: 10, max_offhand_damage: 5},
      player: %Player{},
      internal: %Internal{}
    }

    %{
      attacker: attacker,
      defender: %Mob{unit: %Unit{level: 20, health: 100}, internal: %Internal{}},
      attack: %{caster_level: 20, caster_player?: true, caster_attack_skill: 100, crit_chance: 5.0}
    }
  end

  describe "attacker_context/1" do
    test "uses usable offhand inputs even when derived damage is zero", %{attacker: attacker} do
      assert AttackTable.attacker_context(attacker).dual_wield_penalty?
      zero_damage = %{attacker | unit: %{attacker.unit | max_offhand_damage: 0, base_offhand_max_damage: 0}}
      assert AttackTable.attacker_context(zero_damage).dual_wield_penalty?

      unequipped = %{attacker | unit: %{attacker.unit | base_offhand_max_damage: nil}}
      refute AttackTable.attacker_context(unequipped).dual_wield_penalty?

      feral = %{attacker | unit: %{attacker.unit | class: 11, shapeshift_form: 1}}
      refute AttackTable.attacker_context(feral).dual_wield_penalty?
    end

    test "distinguishes creature offhand weapons from shields", %{defender: defender} do
      for {item_class, expected} <- [{2, true}, {4, false}, {0, false}] do
        creature = %{defender | unit: %{defender.unit | virtual_item_info: <<0::64, item_class, 0::120>>}}
        assert AttackTable.attacker_context(creature).dual_wield_penalty? == expected
      end
    end

    test "restores the penalty when a queued attack is consumed", %{attacker: attacker} do
      spell = %Spell{id: 78, school: :physical}
      queued = MeleeSpell.queue_next_swing(attacker, spell)
      refute AttackTable.attacker_context(queued).dual_wield_penalty?
      assert {consumed, ^spell} = MeleeSpell.consume_next_swing(queued)
      assert AttackTable.attacker_context(consumed).dual_wield_penalty?
    end

    test "suppresses the penalty during physical casts and auto-repeat", %{attacker: attacker} do
      for field <- [:casting, :auto_shot], school <- [:physical, :fire] do
        cast = %Cast{spell: %Spell{id: 1, school: school}}
        internal = struct!(attacker.internal, [{field, cast}])

        assert AttackTable.attacker_context(%{attacker | internal: internal}).dual_wield_penalty? ==
                 (school != :physical)
      end
    end
  end

  describe "resolve/4" do
    test "adds nineteen percent miss to both dual-wield white swings", context do
      swing = Map.merge(context.attack, AttackTable.attacker_context(context.attacker))

      for offhand? <- [false, true] do
        swing = Map.put(swing, :offhand?, offhand?)
        assert AttackTable.resolve(context.defender, swing, 100, roll: 2_399).outcome == :miss
        assert AttackTable.resolve(context.defender, swing, 100, roll: 2_400).outcome == :dodge
      end

      boosted = Map.put(swing, :hit_chance_bonus, 19)
      assert AttackTable.resolve(context.defender, boosted, 100, roll: 499).outcome == :miss
      assert AttackTable.resolve(context.defender, boosted, 100, roll: 500).outcome == :dodge
    end

    test "applies hit bonuses after scaling low-level creature miss", context do
      defender = %{context.defender | unit: %{context.defender.unit | level: 5}}
      attack = %{context.attack | caster_level: 5, caster_attack_skill: 25}
      attack = Map.put(attack, :hit_chance_bonus, 2)
      assert AttackTable.resolve(defender, attack, 100, roll: 49).outcome == :miss
      assert AttackTable.resolve(defender, attack, 100, roll: 50).outcome == :dodge
    end

    test "ignores the first hit point beyond ten defense advantage", context do
      defender = %{context.defender | unit: %{context.defender.unit | level: 23}}

      for {hit, boundary} <- [{0, 800}, {1, 800}, {8, 100}, {9, 0}, {-1, 900}] do
        attack = Map.put(context.attack, :hit_chance_bonus, hit)
        if boundary > 0, do: assert(AttackTable.resolve(defender, attack, 100, roll: boundary - 1).outcome == :miss)
        refute AttackTable.resolve(defender, attack, 100, roll: boundary).outcome == :miss
      end

      attack = context.attack |> Map.put(:caster_attack_skill, 105) |> Map.put(:hit_chance_bonus, 6)
      refute AttackTable.resolve(defender, attack, 100, roll: 0).outcome == :miss
    end

    test "target hit modifiers bypass attacker hit suppression", context do
      aura = %Holder{auras: [%Aura{type: :mod_attacker_melee_hit_chance, amount: 1}]}
      defender = %{context.defender | unit: %{context.defender.unit | level: 23, auras: [aura]}}
      assert AttackTable.resolve(defender, context.attack, 100, roll: 699).outcome == :miss
      refute AttackTable.resolve(defender, context.attack, 100, roll: 700).outcome == :miss

      ranged = Map.put(context.attack, :ranged?, true)
      assert AttackTable.resolve(defender, ranged, 100, roll: 700).outcome == :miss
    end

    test "extra skill improves glancing damage without reducing its frequency", context do
      defender = %{context.defender | unit: %{context.defender.unit | level: 23, flags: 0x40000}}

      for {skill, boundary, damage} <- [{100, 4_800, 550}, {105, 4_600, 800}] do
        attack = %{context.attack | caster_attack_skill: skill}
        result = AttackTable.resolve(defender, attack, 1_000, roll: boundary - 1, glance_roll: 0.0)
        assert result.outcome == :glancing
        assert result.damage == damage
        refute AttackTable.resolve(defender, attack, 1_000, roll: boundary).outcome == :glancing
      end
    end

    test "caps weapon skill for creature parry", context do
      attack = %{context.attack | caster_attack_skill: 105}
      assert AttackTable.resolve(context.defender, attack, 100, roll: 1_399).outcome == :parry
      assert AttackTable.resolve(context.defender, attack, 100, roll: 1_400).outcome == :glancing
    end

    test "wand classes receive their glancing damage penalty", context do
      for class <- [5, 8, 9] do
        attack = Map.put(context.attack, :caster_class, class)
        result = AttackTable.resolve(context.defender, attack, 1_000, roll: 1_500, glance_roll: 0.0)
        assert result.outcome == :glancing
        assert result.damage == 600
      end
    end
  end

  describe "roll_special/3" do
    test "specials and ranged attacks ignore the dual-wield penalty", context do
      attack = Map.put(context.attack, :dual_wield_penalty?, true)
      assert AttackTable.roll_special(context.defender, attack, roll: 499).outcome == :miss
      assert AttackTable.roll_special(context.defender, attack, roll: 500).outcome == :dodge

      ranged = Map.put(attack, :ranged?, true)
      assert AttackTable.roll_special(context.defender, ranged, roll: 500, crit_roll: 9_999).outcome == :normal
      assert AttackTable.roll_special(context.defender, ranged, roll: 1_500, crit_roll: 9_999).outcome == :normal
      assert AttackTable.resolve(context.defender, ranged, 100, roll: 2_000).outcome == :normal
    end

    test "caps negative creature crit adjustment at the attacker's level", context do
      defender = %{context.defender | unit: %{context.defender.unit | level: 23}}

      for skill <- [100, 105, 110] do
        attack = %{context.attack | caster_attack_skill: skill}
        assert AttackTable.roll_special(defender, attack, roll: 9_999, crit_roll: 199).outcome == :crit
        assert AttackTable.roll_special(defender, attack, roll: 9_999, crit_roll: 200).outcome == :normal
      end
    end

    test "uses maximum player defense against players and current defense against creatures", context do
      defender = %{context.attacker | player: %Player{skills: %{95 => %{value: 1, max: 100}}}}
      creature_attack = %{context.attack | caster_player?: false}
      assert AttackTable.roll_special(defender, context.attack, roll: 150).outcome == :miss
      refute AttackTable.roll_special(defender, creature_attack, roll: 150).outcome == :miss
      assert AttackTable.roll_special(defender, context.attack, roll: 9_999, crit_roll: 500).outcome == :normal
      assert AttackTable.roll_special(defender, creature_attack, roll: 9_999, crit_roll: 500).outcome == :crit
    end
  end

  describe "defense_value/2" do
    test "includes both defense bonuses with either skill basis", context do
      auras = [
        %Holder{
          auras: [
            %Aura{type: :mod_skill, misc_value: 95, amount: 5},
            %Aura{type: :mod_skill_talent, misc_value: 95, amount: 10}
          ]
        }
      ]

      defender = %{
        context.attacker
        | unit: %{context.attacker.unit | auras: auras},
          player: %Player{skills: %{95 => %{value: 1, max: 100}}}
      }

      assert Skills.defense_value(defender) == 16
      assert Skills.defense_value(defender, true) == 115
    end
  end
end
