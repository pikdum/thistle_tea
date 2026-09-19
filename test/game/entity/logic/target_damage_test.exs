defmodule ThistleTea.Game.Entity.Logic.TargetDamageTest do
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
  alias ThistleTea.Game.Entity.Logic.TargetDamage
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:entities]

  describe "bonus/2" do
    test "combines equipment and stacked auras by live creature type", %{caster: caster, target: target} do
      caster = %{
        caster
        | unit: %{
            caster.unit
            | auras: [holder(:mod_damage_done_creature, 6, 9, 2)],
              equipment_bonuses: %{damage_done_creature: [{1, 2}, {8, 4}]}
          }
      }

      snapshot = TargetDamage.snapshot(caster)
      assert TargetDamage.bonus(target, snapshot) == 14
      assert TargetDamage.bonus(with_type(target, 4), snapshot) == 16
      assert TargetDamage.bonus(with_type(target, 6), snapshot) == 0
      assert TargetDamage.bonus(caster, snapshot) == 0
      cat = %{caster | unit: %{caster.unit | shapeshift_form: 1}}
      assert TargetDamage.bonus(cat, snapshot) == 14
      assert caster.unit.min_damage == 100
    end
  end

  describe "resolve/4" do
    test "adds flat damage before armor and crits without weapon speed scaling", %{caster: caster, target: target} do
      for speed <- [1_000, 4_000] do
        caster = %{caster | unit: %{caster.unit | base_attack_time: speed}}
        attack = AttackTable.attacker_context(caster)
        assert AttackTable.resolve(target, attack, 100, roll: 9_999).damage == 106
        assert AttackTable.resolve(with_type(target, 7), attack, 100, roll: 9_999).damage == 100
        assert AttackTable.resolve(target, %{attack | crit_chance: 100}, 100, roll: 9_999).damage == 212
        assert AttackTable.resolve(target, attack, 100, roll: 0).damage == 0
        armored = %{target | unit: %{target.unit | normal_resistance: 3_000}}

        assert AttackTable.resolve(armored, attack, 100, roll: 9_999).damage ==
                 AttackTable.armor_reduced_damage(106, 3_000, 60)
      end
    end

    test "scales the added bonus with hand and outgoing damage modifiers", %{caster: caster, target: target} do
      caster = %{
        caster
        | unit: %{
            caster.unit
            | auras: [
                holder(:mod_damage_done_creature, 20, 1),
                holder(:mod_damage_percent_done, 100, 1),
                holder(:mod_offhand_damage_pct, 50),
                holder(:mod_damage_done_versus, 10, 1)
              ]
          }
      }

      attack = AttackTable.attacker_context(caster)
      assert AttackTable.resolve(target, attack, 100, roll: 9_999).damage == 154
      assert AttackTable.resolve(target, Map.put(attack, :offhand?, true), 100, roll: 9_999).damage == 143
    end
  end

  describe "receive/4" do
    test "adds flat magic damage separately from coefficient-scaled spell power", %{caster: caster, target: target} do
      spell = damage_spell()
      context = %{context(caster, spell) | spell_damage_bonus: %{holy: 20}}
      {damaged, events} = SpellEffect.receive(target, context, spell, 0)
      assert damage(events) == 116
      assert damaged.unit.health == 884
      {_, events} = SpellEffect.receive(with_type(target, 7), context, spell, 0)
      assert damage(events) == 110
      {_, events} = SpellEffect.receive(target, %{context | spell_crit_chance: 100}, spell, 0)
      assert damage(events) == 174
    end

    test "adds weapon bonuses once after weapon percentage for melee and ranged", %{caster: caster, target: target} do
      for damage_class <- [2, 3] do
        spell = %Spell{
          id: 90_003,
          school: :physical,
          dmg_class: damage_class,
          effects: [
            %Effect{index: 0, type: :normalized_weapon_damage, base_points: 10},
            %Effect{index: 1, type: :weapon_percent_damage, base_points: 150}
          ]
        }

        context = %{
          context(caster, spell)
          | attack_power: 0,
            weapon_base_min: 100,
            weapon_base_max: 100,
            attack_time_ms: 2_000,
            normalized_speed: 2.4
        }

        {_, events} = SpellEffect.receive(target, context, spell, 0)
        assert damage(events) == 171
      end
    end

    test "coefficient-scales non-weapon melee and ranged damage", %{caster: caster, target: target} do
      for damage_class <- [2, 3] do
        spell = %{damage_spell() | dmg_class: damage_class}
        {_, events} = SpellEffect.receive(target, context(caster, spell), spell, 0)
        assert damage(events) == 103
      end
    end

    test "excludes fixed damage, ignored caster modifiers, Ignite, and healing", %{caster: caster, target: target} do
      spell = damage_spell()

      for spell <- [
            %{spell | custom_flags: 0x010},
            %{spell | attributes: MapSet.new([:ignore_caster_modifiers])},
            %{spell | id: 12_654}
          ] do
        {_, events} = SpellEffect.receive(target, context(caster, spell), spell, 0)
        assert damage(events) == 100
      end

      heal = %{spell | effects: [%{hd(spell.effects) | type: :heal}]}
      hurt = %{target | unit: %{target.unit | health: 500}}
      {healed, _events} = SpellEffect.receive(hurt, context(caster, heal), heal, 0)
      assert healed.unit.health == 600
    end

    test "leech transfers actual health lost including the bonus", %{caster: caster, target: target} do
      spell = damage_spell(:health_leech)
      {damaged, events} = SpellEffect.receive(target, context(caster, spell), spell, 0)
      assert damaged.unit.health == 894
      assert Enum.any?(events, &match?(%Effects.HealEntity{amount: 106}, &1))
      target = %{target | unit: %{target.unit | health: 102}}
      {_, events} = SpellEffect.receive(target, context(caster, spell), spell, 0)
      assert Enum.any?(events, &match?(%Effects.HealEntity{amount: 102}, &1))
    end
  end

  describe "tick/2" do
    test "snapshots flat magic and scaled physical bonuses once per periodic application", %{
      caster: caster,
      target: target
    } do
      for {damage_class, expected} <- [{1, 106}, {2, 103}, {3, 103}],
          type <- [:periodic_damage, :periodic_leech] do
        spell = periodic_spell(type, damage_class)
        {affected, _events} = SpellEffect.receive(target, context(caster, spell), spell, 0)
        assert hd(hd(affected.unit.auras).auras).amount == expected
        {ticked, events} = Aura.tick(affected, 1_000)
        assert damage(events) == expected
        assert ticked.unit.health == 1_000 - expected
        {ticked, events} = Aura.tick(ticked, 2_000)
        assert damage(events) == expected
        assert ticked.unit.health == 1_000 - 2 * expected
        unbuffed = %{caster | unit: %{caster.unit | auras: []}}
        {refreshed, _events} = Aura.apply_spell(ticked, context(unbuffed, spell), spell, 2_000)
        assert hd(hd(refreshed.unit.auras).auras).amount == 100
        {expired, _events} = Aura.tick(refreshed, 5_000)
        assert expired.unit.auras == []
      end
    end

    test "does not increase periodic healing or percentage health damage", %{caster: caster, target: target} do
      for type <- [:periodic_heal, :periodic_damage_percent] do
        spell = periodic_spell(type, 1)
        {affected, _events} = SpellEffect.receive(target, context(caster, spell), spell, 0)
        assert hd(hd(affected.unit.auras).auras).amount == 100
      end
    end
  end

  describe "apply_spell/5" do
    test "cancellation, expiry, and death remove future bonuses without changing old snapshots", %{caster: caster} do
      caster = %{caster | unit: %{caster.unit | auras: []}}

      spell = %Spell{
        id: 90_004,
        duration_ms: 1_000,
        effects: [%Effect{type: :apply_aura, aura: :mod_damage_done_creature, base_points: 6, misc_value: 1}]
      }

      {buffed, _events} = Aura.apply_spell(caster, 1, 60, spell, 0)
      snapshot = TargetDamage.snapshot(buffed)
      assert snapshot == [{1, 6}]
      assert buffed.unit.min_damage == caster.unit.min_damage
      {cancelled, _events} = Aura.remove_spells(buffed, [spell.id], 500)
      {expired, _events} = Aura.tick(buffed, 1_000)
      dead = Core.take_damage(buffed, 1_000, 500)
      for entity <- [cancelled, expired, dead], do: assert(TargetDamage.snapshot(entity) == [])
      assert snapshot == [{1, 6}]
    end
  end

  defp entities(_context) do
    unit = %Unit{
      health: 1_000,
      max_health: 1_000,
      level: 60,
      class: 1,
      min_damage: 100,
      max_damage: 100,
      base_attack_time: 2_000,
      offhand_attack_time: 1_000,
      auras: [holder(:mod_damage_done_creature, 6, 1)]
    }

    caster = %Character{
      object: %Object{guid: 1},
      player: %Player{},
      unit: unit,
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    target = %Mob{
      object: %Object{guid: 2},
      unit: %{unit | auras: [], flags: 0x00040000},
      internal: %Internal{creature: %Creature{creature_type: 1}}
    }

    %{caster: caster, target: target}
  end

  defp holder(type, amount, mask \\ 0, stacks \\ 1) do
    %Holder{
      spell: %Spell{id: 90_000},
      caster_guid: 1,
      stacks: stacks,
      auras: [%AuraData{type: type, amount: amount, misc_value: mask}]
    }
  end

  defp with_type(entity, type),
    do: %{entity | internal: %{entity.internal | creature: %{entity.internal.creature | creature_type: type}}}

  defp damage_spell(type \\ :school_damage) do
    %Spell{
      id: 90_001,
      school: :holy,
      dmg_class: 1,
      effects: [%Effect{index: 0, type: type, base_points: 100, bonus_coefficient: 0.5, multiple_value: 1.0}]
    }
  end

  defp periodic_spell(type, damage_class) do
    %Spell{
      id: 90_002,
      school: :holy,
      dmg_class: damage_class,
      duration_ms: 3_000,
      effects: [
        %Effect{
          index: 0,
          type: :apply_aura,
          aura: type,
          base_points: 100,
          bonus_coefficient: 0.5,
          amplitude_ms: 1_000,
          multiple_value: 1.0
        }
      ]
    }
  end

  defp context(caster, spell) do
    %{
      CastContext.from_caster(caster, spell, 2)
      | hit_chance_bonus: 100,
        melee_crit_chance: 0,
        spell_crit_chance: 0,
        caster_position: nil
    }
  end

  defp damage(events),
    do: Enum.find_value(events, fn event -> if match?(%Effects.SpellDamage{}, event), do: event.damage end)
end
