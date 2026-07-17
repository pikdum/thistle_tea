defmodule ThistleTea.Game.Entity.Logic.WarriorSpellsTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Scripts
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.WorldRef

  @battle_form 17
  @defensive_form 18

  @battle_stance_mask 0x10000
  @berserker_stance_mask 0x40000

  defp warrior_fixture(opts \\ []) do
    %Character{
      object: %Object{guid: 5},
      unit: %Unit{
        class: 1,
        level: 10,
        health: 100,
        max_health: 100,
        power_type: 1,
        power2: Keyword.get(opts, :rage, 0),
        max_power2: 1_000,
        shapeshift_form: Keyword.get(opts, :form, 0),
        auras: [],
        flags: 0
      },
      player: %Player{flags: 0},
      internal: %Internal{world: %WorldRef{map_id: 0}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp stance_spell(id, form, opts \\ []) do
    %Spell{
      id: id,
      name: Keyword.get(opts, :name, "Stance #{id}"),
      school: :physical,
      duration_ms: -1,
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :mod_shapeshift, base_points: -1, misc_value: form},
        %Effect{
          index: 1,
          type: :apply_aura,
          aura: :mod_threat,
          base_points: Keyword.get(opts, :threat, -21),
          misc_value: 127
        }
      ]
    }
  end

  defp apply_stance(entity, spell) do
    {entity, _events} = Aura.apply_spell(entity, entity.object.guid, 10, spell, 1_000)
    entity
  end

  describe "stance application" do
    test "sets the shapeshift form byte" do
      entity = apply_stance(warrior_fixture(), stance_spell(2457, @battle_form))

      assert entity.unit.shapeshift_form == @battle_form
      assert [%Holder{spell: %Spell{id: 2457}}] = entity.unit.auras
    end

    test "zeroes rage on stance change" do
      entity = apply_stance(warrior_fixture(rage: 500), stance_spell(2457, @battle_form))

      assert entity.unit.power2 == 0
    end

    test "switching stances replaces the previous stance holder" do
      entity =
        warrior_fixture()
        |> apply_stance(stance_spell(2457, @battle_form))
        |> apply_stance(stance_spell(71, @defensive_form))

      assert entity.unit.shapeshift_form == @defensive_form
      assert [%Holder{spell: %Spell{id: 71}}] = entity.unit.auras
    end

    test "removing the stance clears the form byte" do
      entity = apply_stance(warrior_fixture(), stance_spell(2457, @battle_form))

      {entity, _events} = Aura.remove_spells(entity, [2457], 2_000)

      assert entity.unit.shapeshift_form == 0
      assert entity.unit.auras == []
    end
  end

  describe "usable_in_stance?/2" do
    test "spells without stance requirements always pass" do
      assert Spell.usable_in_stance?(%Spell{stances: 0}, 0)
      assert Spell.usable_in_stance?(%Spell{stances: 0}, @battle_form)
    end

    test "stance-locked spells require a matching form" do
      spell = %Spell{stances: @battle_stance_mask}

      assert Spell.usable_in_stance?(spell, @battle_form)
      refute Spell.usable_in_stance?(spell, @defensive_form)
      refute Spell.usable_in_stance?(spell, 0)
    end

    test "combined masks accept any listed stance" do
      spell = %Spell{stances: @battle_stance_mask ||| @berserker_stance_mask}

      assert Spell.usable_in_stance?(spell, @battle_form)
      assert Spell.usable_in_stance?(spell, 19)
      refute Spell.usable_in_stance?(spell, @defensive_form)
    end
  end

  describe "stance cast validation" do
    defp mocking_blow_like do
      %Spell{
        id: 694,
        name: "Mocking Blow",
        school: :physical,
        stances: @battle_stance_mask,
        mana_cost: 0,
        power_type: 1
      }
    end

    test "rejects stance-locked spells outside the stance" do
      caster = warrior_fixture(form: @defensive_form)

      assert {:error, :only_shapeshift} =
               CastValidation.validate(caster, mocking_blow_like(), %Targets{}, nil, 1_000)
    end

    test "accepts stance-locked spells in the required stance" do
      caster = warrior_fixture(form: @battle_form)

      assert :ok = CastValidation.validate(caster, mocking_blow_like(), %Targets{}, nil, 1_000)
    end
  end

  describe "weapon requirement validation" do
    defp shield_block_like do
      %Spell{
        id: 2565,
        name: "Shield Block",
        school: :physical,
        equipped_item_class: 4,
        equipped_item_subclass_mask: 64,
        mana_cost: 0,
        power_type: 1
      }
    end

    test "rejects shield abilities without a shield equipped" do
      caster = warrior_fixture()
      sword = %{class: 2, subclass: 7}

      assert {:error, :equipped_item_class} =
               CastValidation.validate(caster, shield_block_like(), %Targets{}, nil, 1_000, equipped_items: [sword])
    end

    test "accepts shield abilities with a shield equipped" do
      caster = warrior_fixture()
      shield = %{class: 4, subclass: 6}

      assert :ok =
               CastValidation.validate(caster, shield_block_like(), %Targets{}, nil, 1_000, equipped_items: [shield])
    end

    test "weapon masks accept any listed weapon type" do
      caster = warrior_fixture()

      heroic_strike = %Spell{
        id: 78,
        name: "Heroic Strike",
        equipped_item_class: 2,
        equipped_item_subclass_mask: 173_555
      }

      sword = %{class: 2, subclass: 7}
      wand = %{class: 2, subclass: 19}

      assert :ok = CastValidation.validate(caster, heroic_strike, %Targets{}, nil, 1_000, equipped_items: [sword])

      assert {:error, :equipped_item_class} =
               CastValidation.validate(caster, heroic_strike, %Targets{}, nil, 1_000, equipped_items: [wand])
    end
  end

  describe "melee ability resolution" do
    @unit_flag_stunned 0x00040000

    defp melee_target(opts \\ []) do
      helpless? = Keyword.get(opts, :helpless?, true)

      %Mob{
        object: %Object{guid: 9},
        unit: %Unit{
          health: 200,
          max_health: 200,
          level: Keyword.get(opts, :level, 10),
          normal_resistance: Keyword.get(opts, :armor, 0),
          flags: if(helpless?, do: @unit_flag_stunned, else: 0),
          stand_state: if(helpless?, do: 1, else: 0),
          auras: []
        },
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    end

    defp melee_context(spell, opts \\ []) do
      %CastContext{
        caster_guid: 5,
        caster_level: 10,
        caster_type: :player,
        target_guid: 9,
        spell: spell,
        attack_power: Keyword.get(opts, :attack_power, 140),
        weapon_base_min: Keyword.get(opts, :weapon_min, 10),
        weapon_base_max: Keyword.get(opts, :weapon_max, 10),
        attack_time_ms: 2_000,
        normalized_speed: 2.4,
        attack_skill: 50,
        melee_crit_chance: 0.0,
        caster_power: 0
      }
    end

    test "weapon damage effects roll weapon plus attack power plus bonus" do
      spell = %Spell{
        id: 78,
        name: "Heroic Strike",
        school: :physical,
        dmg_class: 2,
        effects: [%Effect{index: 0, type: :weapon_damage_noschool, base_points: 10, die_sides: 1}]
      }

      target = melee_target()

      {target, events} = SpellEffect.receive(target, melee_context(spell), spell, 1_000)

      assert [%Event{type: :spell_damage, damage: 41, crit?: false}] = events
      assert target.unit.health == 159
    end

    test "normalized weapon damage uses the normalized speed for attack power" do
      spell = %Spell{
        id: 7384,
        name: "Overpower",
        school: :physical,
        spell_family: 4,
        family_flags_0: 0x00000004,
        dmg_class: 2,
        effects: [%Effect{index: 0, type: :normalized_weapon_damage, base_points: 4, die_sides: 1}]
      }

      target = melee_target()

      {_target, events} = SpellEffect.receive(target, melee_context(spell), spell, 1_000)

      assert [%Event{type: :spell_damage, damage: 39}] = events
    end

    test "melee-class school damage can be avoided and reports the miss" do
      spell = %Spell{
        id: 1715,
        name: "Hamstring",
        school: :physical,
        dmg_class: 2,
        effects: [%Effect{index: 0, type: :school_damage, base_points: 4, die_sides: 1}]
      }

      target = melee_target(level: 60, helpless?: false)

      {target, events} = SpellEffect.receive(target, melee_context(spell), spell, 1_000)

      assert target.unit.health == 200

      assert [
               %Event{type: :spell_log_miss, source_guid: 5, target_guid: 9, spell_id: 1715},
               %Event{type: :attack_outcome, target_guid: 5, source_guid: 9, spell_id: 1715}
             ] = events
    end
  end

  describe "reactive ability validation" do
    defp revenge_like do
      %Spell{id: 6572, name: "Revenge", school: :physical, caster_aura_state: 1, mana_cost: 0, power_type: 1}
    end

    defp execute_like do
      %Spell{id: 5308, name: "Execute", school: :physical, target_aura_state: 2, mana_cost: 0, power_type: 1}
    end

    test "revenge requires a recent dodge, parry, or block" do
      caster = warrior_fixture()

      assert {:error, :cant_do_that_yet} =
               CastValidation.validate(caster, revenge_like(), %Targets{}, nil, 1_000)

      caster = Reactive.mark_defense(caster, 1_000)

      assert :ok = CastValidation.validate(caster, revenge_like(), %Targets{}, nil, 2_000)
      assert {:error, :cant_do_that_yet} = CastValidation.validate(caster, revenge_like(), %Targets{}, nil, 9_000)
    end

    test "overpower requires a fresh combo point on the target" do
      caster = warrior_fixture(form: @battle_form)

      spell = %Spell{
        id: 7384,
        name: "Overpower",
        school: :physical,
        spell_family: 4,
        family_flags_0: 0x00000004,
        stances: @battle_stance_mask,
        first_in_chain: 7384,
        mana_cost: 0,
        power_type: 1
      }

      targets = %Targets{unit_guid: 77}

      assert {:error, :cant_do_that_yet} = CastValidation.validate(caster, spell, targets, nil, 1_000)

      caster = Reactive.mark_dodging_target(caster, 77, 1_000)

      assert :ok = CastValidation.validate(caster, spell, targets, nil, 2_000)
      assert {:error, :cant_do_that_yet} = CastValidation.validate(caster, spell, targets, nil, 9_000)
    end

    test "execute requires the target under twenty percent health" do
      caster = warrior_fixture()

      assert {:error, :target_aurastate} =
               CastValidation.validate(caster, execute_like(), %Targets{}, %{alive?: true, health_pct: 50}, 1_000)

      assert :ok =
               CastValidation.validate(caster, execute_like(), %Targets{}, %{alive?: true, health_pct: 15}, 1_000)
    end
  end

  describe "execute damage" do
    test "converts remaining rage into damage and drains it on a hit" do
      spell = %Spell{
        id: 5308,
        name: "Execute",
        script_name: "spell_warrior_execute_dummy",
        school: :physical,
        spell_family: 4,
        family_flags_0: 0x20000000,
        dmg_class: 2,
        effects: [
          %Effect{index: 0, type: :dummy, base_points: 124, die_sides: 1, damage_multiplier: 0.3},
          %Effect{index: 1, type: :trigger_spell, trigger_spell_id: 20_647}
        ]
      }

      context = %{melee_context(spell) | caster_power: 200}
      target = melee_target()

      {target, events} = SpellEffect.receive(target, context, spell, 1_000)

      assert [
               %Event{type: :spell_damage, spell_id: 20_647, damage: 185},
               %Event{type: :drain_power, target_guid: 5, misc_value: 1}
             ] = events

      assert target.unit.health == 15
    end

    test "avoided executes do not drain rage" do
      spell = %Spell{
        id: 5308,
        name: "Execute",
        school: :physical,
        dmg_class: 2,
        effects: [%Effect{index: 0, type: :dummy, base_points: 124, die_sides: 1, damage_multiplier: 0.3}]
      }

      context = %{melee_context(spell) | caster_power: 200}
      target = melee_target(level: 60, helpless?: false)

      {_target, events} = SpellEffect.receive(target, context, spell, 1_000)

      refute Enum.any?(events, &(&1.type == :drain_power))
      assert Enum.any?(events, &(&1.type == :spell_log_miss))
    end
  end

  describe "sunder armor stacking" do
    defp sunder_spell do
      %Spell{
        id: 7386,
        name: "Sunder Armor",
        school: :physical,
        duration_ms: 30_000,
        stack_amount: 5,
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :mod_resistance, base_points: -91, die_sides: 1, misc_value: 1}
        ]
      }
    end

    defp armored_mob do
      %Mob{
        object: %Object{guid: 9},
        unit: %Unit{
          health: 200,
          max_health: 200,
          level: 10,
          base_normal_resistance: 1_000,
          normal_resistance: 1_000,
          auras: []
        },
        internal: %Internal{world: %WorldRef{map_id: 0}, in_combat: true},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    end

    test "reapplying sunder stacks up to the cap and scales the armor reduction" do
      mob = armored_mob()

      {mob, _events} = Aura.apply_spell(mob, 5, 10, sunder_spell(), 1_000)
      assert [%Holder{stacks: 1}] = mob.unit.auras
      assert mob.unit.normal_resistance == 910

      {mob, _events} = Aura.apply_spell(mob, 5, 10, sunder_spell(), 2_000)
      assert [%Holder{stacks: 2}] = mob.unit.auras
      assert mob.unit.normal_resistance == 820

      mob =
        Enum.reduce(1..6, mob, fn i, acc ->
          {acc, _events} = Aura.apply_spell(acc, 5, 10, sunder_spell(), 2_000 + i)
          acc
        end)

      assert [%Holder{stacks: 5}] = mob.unit.auras
      assert mob.unit.normal_resistance == 550
    end

    test "uses a visible debuff slot" do
      {mob, _events} = Aura.apply_spell(armored_mob(), 5, 10, sunder_spell(), 1_000)

      assert [%Holder{negative?: true, slot: 32}] = mob.unit.auras

      assert <<spell_id::little-size(32), _rest::binary>> =
               <<mob.unit.aura::little-size(48 * 32)>> |> binary_part(32 * 4, 16 * 4)

      assert spell_id == 7386
    end
  end

  describe "intimidating shout" do
    test "does not apply enemy fear effects to the caster" do
      spell = %Spell{
        id: 5246,
        name: "Intimidating Shout",
        school: :physical,
        duration_ms: 8_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: :mod_fear,
            implicit_target_a: :aoe_enemy_at_caster
          }
        ]
      }

      caster = warrior_fixture()
      context = %CastContext{caster_guid: caster.object.guid, caster_level: 10}

      {caster, _events} = SpellEffect.receive(caster, context, spell, 1_000)

      refute Aura.has_aura?(caster, :mod_fear)
    end
  end

  describe "taunt" do
    defp threatened_mob(threat_table, target) do
      %Mob{
        object: %Object{guid: 9},
        unit: %Unit{health: 200, max_health: 200, level: 10, target: target, auras: []},
        internal: %Internal{world: %WorldRef{map_id: 0}, in_combat: true, threat: threat_table},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    end

    test "attack_me raises the taunter to the top of the threat table" do
      mob = threatened_mob(%{100 => 500.0}, 100)

      spell = %Spell{
        id: 355,
        name: "Taunt",
        school: :physical,
        effects: [%Effect{index: 0, type: :attack_me, base_points: 0}]
      }

      context = %CastContext{caster_guid: 5, caster_level: 10, target_hostile?: true}

      {mob, _events} = SpellEffect.receive(mob, context, spell, 1_000)

      assert mob.internal.threat[5] == 500.0
    end

    test "an active taunt aura forces victim selection onto the taunter" do
      mob = threatened_mob(%{100 => 500.0, 5 => 500.0}, 100)

      taunt_aura = %Spell{
        id: 355,
        name: "Taunt",
        school: :physical,
        duration_ms: 3_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_taunt, base_points: 0}]
      }

      {mob, _events} = Aura.apply_spell(mob, 5, 10, taunt_aura, 1_000)

      {_mob, decision} = Threat.reselect(mob, valid?: fn _guid -> true end, in_melee?: fn _guid -> true end)

      assert decision == {:switch, 5}
    end

    test "without the taunt aura equal threat keeps the current victim" do
      mob = threatened_mob(%{100 => 500.0, 5 => 500.0}, 100)

      {_mob, decision} = Threat.reselect(mob, valid?: fn _guid -> true end, in_melee?: fn _guid -> true end)

      assert decision == :keep
    end
  end

  describe "bonus spell threat" do
    test "flat spell threat lands on the mob scaled by the stance multiplier" do
      mob = %Mob{
        object: %Object{guid: 9},
        unit: %Unit{health: 200, max_health: 200, level: 10, auras: []},
        internal: %Internal{world: %WorldRef{map_id: 0}, in_combat: true, threat: %{}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      spell = %Spell{
        id: 7386,
        name: "Sunder Armor",
        school: :physical,
        duration_ms: 30_000,
        stack_amount: 5,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_resistance, base_points: -91, misc_value: 1}]
      }

      context = %CastContext{
        caster_guid: 5,
        caster_level: 10,
        target_hostile?: true,
        spell_threat: %{threat: 45.0, multiplier: 1.0},
        threat_multiplier: 1.3
      }

      {mob, _events} = SpellEffect.receive(mob, context, spell, 1_000)

      assert_in_delta mob.internal.threat[5], 58.5, 0.001
    end
  end

  describe "dodged melee abilities" do
    test "a dodged ability applies none of its effects" do
      spell = %Spell{
        id: 1715,
        name: "Hamstring",
        school: :physical,
        dmg_class: 2,
        duration_ms: 15_000,
        effects: [
          %Effect{index: 0, type: :school_damage, base_points: 4, die_sides: 1},
          %Effect{index: 1, type: :apply_aura, aura: :mod_decrease_speed, base_points: -41}
        ]
      }

      target = melee_target(level: 60, helpless?: false)

      {target, events} = SpellEffect.receive(target, melee_context(spell), spell, 1_000)

      assert target.unit.health == 200
      assert target.unit.auras == []
      assert Enum.any?(events, &(&1.type == :spell_log_miss))
    end
  end

  describe "defensive and utility auras" do
    defp buffed(entity, id, aura, base_points, opts \\ []) do
      spell = %Spell{
        id: id,
        name: "Buff #{id}",
        school: :physical,
        duration_ms: 10_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: aura,
            base_points: base_points,
            die_sides: 1,
            misc_value: Keyword.get(opts, :misc_value, 0)
          }
        ]
      }

      {entity, _events} = Aura.apply_spell(entity, entity.object.guid, 10, spell, 1_000)
      entity
    end

    test "melee haste slows attack speed when negative" do
      entity = warrior_fixture()
      entity = %{entity | unit: %{entity.unit | base_attack_time: 2_000}}

      assert Combat.attack_speed_ms(entity) == 2_000

      entity = buffed(entity, 6343, :mod_melee_haste, -11)

      assert Combat.attack_speed_ms(entity) == 2_222
    end

    test "shield wall cuts damage taken" do
      entity = %{warrior_fixture() | unit: %{warrior_fixture().unit | health: 500, max_health: 500}}
      entity = buffed(entity, 871, :mod_damage_percent_taken, -76, misc_value: 127)

      {entity, _absorbed} = Core.take_damage_with_absorb(entity, 100, 1_000, school: :physical, source: 99)

      assert entity.unit.health == 475
    end

    test "recklessness raises the attacker crit chance" do
      entity = warrior_fixture()

      base = AttackTable.attacker_context(entity).crit_chance

      entity = buffed(entity, 1719, :mod_crit_percent, 99)

      assert AttackTable.attacker_context(entity).crit_chance == base + 100
    end

    test "shield block forces blocks" do
      defender = warrior_fixture()
      attack = %{caster: 99, caster_level: 10, caster_player?: false, crit_chance: 5.0}

      without_block = AttackTable.resolve(defender, attack, 100, roll: 4_000)
      refute without_block.outcome == :block

      defender = buffed(defender, 2565, :mod_block_percent, 74)
      with_block = AttackTable.resolve(defender, attack, 100, roll: 4_000)

      assert with_block.outcome == :block
    end

    test "disarm halves weapon damage and sets the unit flag" do
      entity = warrior_fixture()
      entity = %{entity | unit: %{entity.unit | min_damage: 40.0, max_damage: 60.0}}

      assert Combat.damage_range(entity) == {40.0, 60.0}

      entity = buffed(entity, 676, :mod_disarm, -1)

      assert Combat.damage_range(entity) == {20.0, 30.0}
      assert Bitwise.band(entity.unit.flags, 0x00200000) == 0x00200000
    end

    test "death wish scales physical damage done" do
      entity = warrior_fixture()
      entity = %{entity | unit: %{entity.unit | min_damage: 40.0, max_damage: 60.0}}
      entity = buffed(entity, 12_328, :mod_damage_percent_done, 19, misc_value: 127)

      assert Combat.damage_range(entity) == {48.0, 72.0}
    end
  end

  describe "charge" do
    test "caster-targeted energize routes rage back to the caster" do
      spell = %Spell{
        id: 100,
        name: "Charge",
        school: :physical,
        effects: [
          %Effect{index: 1, type: :energize, base_points: 89, die_sides: 1, misc_value: 1, implicit_target_a: :caster}
        ]
      }

      target = melee_target()
      context = %CastContext{caster_guid: 5, caster_level: 10, target_hostile?: true}

      {target, events} = SpellEffect.receive(target, context, spell, 1_000)

      assert [%Event{type: :grant_power, target_guid: 5, misc_value: 1, amount: 90}] = events
      assert target.unit.power2 in [nil, 0]
    end

    test "completing a charge cast queues the charge movement event" do
      alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT

      spell = %Spell{
        id: 100,
        name: "Charge",
        school: :physical,
        cast_time_ms: 0,
        effects: [%Effect{index: 0, type: :charge, implicit_target_a: :target_enemy}]
      }

      character = warrior_fixture()
      casting = Cast.new(spell, %Targets{unit_guid: 9, raw: <<0::16>>}, 1_000)
      character = %{character | internal: %{character.internal | casting: casting}}

      character = SpellBT.complete_cast(character, 1_000)

      assert Enum.any?(character.internal.events, &(&1.type == :charge and &1.target_guid == 9))
    end
  end

  describe "talent actives" do
    test "bloodthirst scales its damage from attack power" do
      spell = %Spell{
        id: 23_881,
        name: "Bloodthirst",
        script_name: "spell_warrior_bloodthirst",
        school: :physical,
        spell_family: 4,
        family_flags_0: 0x02000000,
        dmg_class: 2,
        effects: [%Effect{index: 0, type: :school_damage, base_points: 44, die_sides: 1}]
      }

      target = melee_target()
      context = %{melee_context(spell) | attack_power: 140}

      {_target, events} = SpellEffect.receive(target, context, spell, 1_000)

      assert [%Event{type: :spell_damage, damage: 63}] = events
    end

    test "last stand triggers its health buff on the caster" do
      spell = %Spell{
        id: 12_975,
        name: "Last Stand",
        school: :physical,
        effects: [%Effect{index: 0, type: :dummy, base_points: 0}]
      }

      caster = warrior_fixture()
      context = %CastContext{caster_guid: 5, caster_level: 10}

      {_caster, events} = SpellEffect.receive(caster, context, spell, 1_000)

      buff_id = Scripts.last_stand_health_buff_id()

      assert [%Event{type: :trigger_spell, target_guid: 5, spell_id: ^buff_id}] = events
    end

    test "the last stand buff raises max health by thirty percent and heals it" do
      buff = %Spell{
        id: Scripts.last_stand_health_buff_id(),
        name: "Last Stand",
        school: :physical,
        duration_ms: 20_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_increase_health, base_points: 0}]
      }

      entity = warrior_fixture()

      entity = %{
        entity
        | unit: %{entity.unit | base_health: 100, health: 50, max_health: 100}
      }

      {entity, _events} = Aura.apply_spell(entity, 5, 10, buff, 1_000)

      assert entity.unit.max_health == 130
      assert entity.unit.health == 80

      {entity, _events} = Aura.remove_spells(entity, [buff.id], 5_000)

      assert entity.unit.max_health == 100
      assert entity.unit.health == 80
    end
  end

  describe "next-swing cancel toggle" do
    test "cancel request clears a queued next-swing spell" do
      character = warrior_fixture()
      spell = %Spell{id: 78, name: "Heroic Strike", attributes: MapSet.new([:on_next_swing])}
      character = %{character | internal: %{character.internal | next_swing_spell: spell}}

      state = Spellcasting.cancel_cast_request(%{character: character})

      assert state.character.internal.next_swing_spell == nil
    end
  end
end
