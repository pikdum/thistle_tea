defmodule ThistleTea.Game.Entity.Logic.RogueSpellsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Targets

  defp rogue(opts \\ []) do
    %Character{
      object: %Object{guid: 5},
      unit: %Unit{
        class: 4,
        level: 60,
        health: 1_000,
        max_health: 1_000,
        power_type: 3,
        power4: 100,
        max_power4: 100,
        shapeshift_form: 0,
        auras: [],
        flags: 0
      },
      player: %Player{flags: 0},
      internal: %Internal{in_combat: Keyword.get(opts, :in_combat, false)},
      movement_block: %MovementBlock{
        position: {0.0, 0.0, 0.0, 0.0},
        base_walk_speed: 2.5,
        base_run_speed: 7.0,
        base_run_back_speed: 4.5,
        walk_speed: 2.5,
        run_speed: 7.0,
        run_back_speed: 4.5
      }
    }
  end

  defp target do
    %Character{
      object: %Object{guid: 9},
      unit: %Unit{level: 60, health: 1_000, max_health: 1_000, auras: [], flags: 0},
      player: %Player{},
      internal: %Internal{}
    }
  end

  describe "combo points" do
    test "builders accumulate to five on one target and reset when changing target" do
      entity = rogue() |> Reactive.add_combo_points(9, 2) |> Reactive.add_combo_points(9, 4)

      assert entity.player.field_combo_target == 9
      assert entity.player.combo_points == 5
      assert Reactive.combo_active?(entity, 9, 100_000)

      entity = Reactive.add_combo_points(entity, 10, 1)
      assert entity.player.field_combo_target == 10
      assert entity.player.combo_points == 1
    end

    test "finishers require points on their selected target" do
      eviscerate = %Spell{
        id: 6760,
        name: "Eviscerate",
        power_type: 3,
        mana_cost: 35,
        attributes: MapSet.new([:finishing_move])
      }

      entity = Reactive.add_combo_points(rogue(), 9, 2)

      assert :ok = CastValidation.validate(entity, eviscerate, Targets.unit(9), nil, 1_000)

      assert {:error, :cant_do_that_yet} =
               CastValidation.validate(entity, eviscerate, Targets.unit(10), nil, 1_000)
    end

    test "eviscerate damage scales with the spent points" do
      spell = %Spell{
        id: 6760,
        name: "Eviscerate",
        school: :physical,
        attributes: MapSet.new([:finishing_move]),
        effects: [
          %Effect{index: 0, type: :school_damage, base_points: 10, die_sides: 0, points_per_combo: 10.0}
        ]
      }

      context = %CastContext{caster_guid: 5, caster_level: 60, combo_points: 4, spell: spell}
      {victim, _events} = SpellEffect.receive(target(), context, spell, 1_000)

      assert victim.unit.health == 950
    end

    test "eviscerate's VMangos-scripted attack-power bonus uses its DBC family flag" do
      eviscerate = %Spell{
        id: 6760,
        school: :physical,
        dmg_class: 2,
        spell_family: 8,
        family_flags_0: 0x00020000,
        attributes: MapSet.new([:ability, :finishing_move]),
        effects: [%Effect{index: 0, type: :school_damage, base_points: 0, die_sides: 0}]
      }

      context = %CastContext{
        caster_guid: 5,
        caster_level: 60,
        attack_power: 100,
        combo_points: 5,
        spell: eviscerate
      }

      {victim, _events} = SpellEffect.receive(target(), context, eviscerate, 1_000)

      assert victim.unit.health == 985
    end

    test "expose armor applies its combo-scaled debuff" do
      spell = %Spell{
        id: 8647,
        name: "Expose Armor",
        duration_ms: 30_000,
        attributes: MapSet.new([:finishing_move]),
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: :mod_resistance,
            base_points: -1,
            points_per_combo: -80.0,
            misc_value: 1,
            implicit_target_a: :target_enemy
          }
        ]
      }

      context = %CastContext{caster_guid: 5, caster_level: 60, combo_points: 5, spell: spell}
      victim = %{target() | unit: %{target().unit | base_normal_resistance: 500, normal_resistance: 500}}
      {victim, _events} = SpellEffect.receive(victim, context, spell, 1_000)

      assert victim.unit.normal_resistance == 99
      assert Aura.has_spell?(victim, 8647)
    end

    test "offensive finisher duration interpolates DBC base and maximum duration" do
      rupture = %Spell{
        id: 1943,
        duration_ms: 6_000,
        max_duration_ms: 16_000,
        attributes: MapSet.new([:finishing_move]),
        effects: [%Effect{index: 0, type: :apply_aura, aura: :periodic_damage, implicit_target_a: :target_enemy}]
      }

      context = %CastContext{caster_guid: 5, caster_level: 60, target_guid: 9, combo_points: 3, spell: rupture}
      {victim, _events} = Aura.apply_spell(target(), context, rupture, 1_000)

      assert [%{expires_at: 13_000}] = victim.unit.auras
    end

    test "mixed rogue abilities apply caster buffs only to the rogue" do
      ghostly_strike = %Spell{
        id: 14_278,
        name: "Ghostly Strike",
        duration_ms: 7_000,
        effects: [
          %Effect{index: 0, type: :weapon_percent_damage, base_points: 125, implicit_target_a: :target_enemy},
          %Effect{index: 1, type: :apply_aura, aura: :mod_dodge, base_points: 15, implicit_target_a: :caster}
        ]
      }

      context = %CastContext{caster_guid: 5, caster_level: 60, spell: ghostly_strike}
      {victim, _events} = SpellEffect.receive(target(), context, ghostly_strike, 1_000)
      {caster, _events} = SpellEffect.receive(rogue(), context, ghostly_strike, 1_000)

      refute Aura.has_spell?(victim, 14_278)
      assert Aura.has_spell?(caster, 14_278)
      assert Aura.flat_amount(caster, :mod_dodge) == 15
    end
  end

  describe "positional requirements" do
    test "backstab requires the rogue to be behind the target" do
      backstab = %Spell{
        id: 53,
        name: "Backstab",
        attributes: MapSet.new([:from_behind]),
        power_type: 3,
        mana_cost: 60
      }

      target_info = %{
        alive?: true,
        hostile?: true,
        attackable?: true,
        position: {0, 0.0, 0.0, 0.0},
        orientation: 0.0
      }

      front = rogue()
      front = %{front | movement_block: %{front.movement_block | position: {1.0, 0.0, 0.0, 0.0}}}
      behind = rogue()
      behind = %{behind | movement_block: %{behind.movement_block | position: {-1.0, 0.0, 0.0, 0.0}}}

      assert {:error, :not_behind} = CastValidation.validate(front, backstab, Targets.unit(9), target_info, 1_000)
      assert :ok = CastValidation.validate(behind, backstab, Targets.unit(9), target_info, 1_000)
    end
  end

  describe "stealth and vanish" do
    test "stealth sets the rogue form and breaks on a hostile cast" do
      stealth = %Spell{
        id: 1784,
        name: "Stealth",
        duration_ms: -1,
        aura_interrupt_flags: 0x3C07,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stealth, base_points: 5}]
      }

      {entity, _events} = Aura.apply_spell(rogue(), 5, 60, stealth, 1_000)
      assert entity.unit.shapeshift_form == 30
      assert Bitwise.band(entity.unit.vis_flag, 0x02) != 0
      assert Bitwise.band(entity.player.field_bytes2_flags, 0x20) != 0

      entity = Aura.break_on_damage(entity, 2_000)
      assert entity.unit.shapeshift_form == 0
      assert entity.unit.auras == []
      assert Bitwise.band(entity.unit.vis_flag, 0x02) == 0
      assert Bitwise.band(entity.player.field_bytes2_flags, 0x20) == 0
    end

    test "ordinary stealth is unavailable in combat but vanish remains available" do
      stealth = %Spell{id: 1784, name: "Stealth", attributes: MapSet.new([:not_in_combat])}
      vanish = %Spell{id: 1856, name: "Vanish"}

      assert {:error, :affecting_combat} =
               CastValidation.validate(rogue(in_combat: true), stealth, %Targets{}, nil, 1_000)

      assert :ok = CastValidation.validate(rogue(in_combat: true), vanish, %Targets{}, nil, 1_000)
    end

    test "cold blood forces the next melee ability to crit" do
      cold_blood = %Spell{
        id: 14_177,
        duration_ms: -1,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :force_crit}]
      }

      {entity, _events} = Aura.apply_spell(rogue(), 5, 60, cold_blood, 1_000)
      context = CastContext.from_caster(entity, %Spell{dmg_class: 2}, 9)

      assert context.melee_crit_chance == 100.0
    end

    test "preparation resets core rogue cooldowns without resetting itself" do
      entity = rogue()

      internal = %{
        entity.internal
        | cooldowns: %{
            2094 => 10_000,
            14_177 => 10_000,
            {:category, 39} => 10_000,
            {:category, 44} => 10_000,
            14_185 => 20_000
          },
          spellbook: %{
            2094 => %Spell{id: 2094, spell_family: 8, recovery_time_ms: 300_000},
            14_177 => %Spell{id: 14_177, spell_family: 8, recovery_time_ms: 180_000},
            1856 => %Spell{id: 1856, spell_family: 8, category: 39, category_recovery_time_ms: 300_000},
            2983 => %Spell{id: 2983, spell_family: 8, category: 44, category_recovery_time_ms: 300_000},
            14_185 => %Spell{id: 14_185, spell_family: 0, recovery_time_ms: 600_000}
          }
      }

      preparation = %Spell{id: 14_185, name: "Preparation", effects: [%Effect{index: 0, type: :dummy}]}
      context = %CastContext{caster_guid: 5, caster_level: 60, spell: preparation}
      {entity, _events} = SpellEffect.receive(%{entity | internal: internal}, context, preparation, 1_000)

      refute Cooldowns.on_cooldown?(entity, %Spell{id: 14_177}, 1_000)
      refute Cooldowns.on_cooldown?(entity, %Spell{id: 2094}, 1_000)
      refute Cooldowns.on_cooldown?(entity, %Spell{id: 1856, category: 39}, 1_000)
      assert Cooldowns.on_cooldown?(entity, preparation, 1_000)
    end

    test "vanish purge removes roots and slows while granting temporary immunity" do
      root = %Spell{
        id: 100,
        duration_ms: 10_000,
        mechanic: 7,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_root}]
      }

      purge = %Spell{
        id: 18_461,
        duration_ms: 1_000,
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :mechanic_immunity, misc_value: 7},
          %Effect{index: 1, type: :apply_aura, aura: :mechanic_immunity, misc_value: 11}
        ]
      }

      {entity, _events} = Aura.apply_spell(rogue(), 9, 60, root, 1_000)
      {entity, _events} = Aura.apply_spell(entity, 5, 60, purge, 2_000)

      refute Aura.has_spell?(entity, 100)
      assert Aura.has_spell?(entity, 18_461)
      assert Aura.mechanic_immune?(entity, root)
    end

    test "vanish drops combat and asks every threatening mob to forget the rogue" do
      entity = rogue(in_combat: true)
      stealth = %Spell{id: 1787, name: "Stealth", rank: 4, spell_family: 8, family_flags_0: 0x00400000}

      internal = %{
        entity.internal
        | threat_refs: MapSet.new([{101, 1}, {102, 1}]),
          last_hostile_time: 900,
          spellbook: %{1787 => stealth},
          blackboard: %Blackboard{auto_attacking: true}
      }

      entity = %{entity | internal: internal}
      entity = %{entity | unit: %{entity.unit | target: 9}}

      vanish = %Spell{
        id: 1856,
        name: "Vanish",
        spell_family: 8,
        family_flags_0: 0x00000800,
        effects: [%Effect{index: 0, type: :clear_threat}]
      }

      context = %CastContext{caster_guid: 5, caster_level: 60, spell: vanish}

      {entity, events} = SpellEffect.receive(entity, context, vanish, 1_000)

      refute entity.internal.in_combat
      refute entity.internal.blackboard.auto_attacking
      assert entity.internal.threat_refs == MapSet.new()
      assert entity.internal.undetectable_until == 2_000
      assert Enum.count(events, &(&1.type == :drop_threat)) == 2
      assert Enum.any?(events, &(&1.type == :drop_nearby_threat))
      assert Enum.any?(events, &(&1.type == :attack_stop and &1.target_guid == 9))
      assert Enum.any?(events, &(&1.type == :trigger_spell and &1.spell_id == 1787))
    end

    test "vanish removes stalked auras as required by the VMangos spell script" do
      marked = %Spell{
        id: 1130,
        duration_ms: 120_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stalked}]
      }

      vanish = %Spell{
        id: 1856,
        spell_family: 8,
        family_flags_0: 0x00000800,
        effects: [%Effect{index: 0, type: :clear_threat}]
      }

      {entity, _events} = Aura.apply_spell(rogue(), 9, 60, marked, 1_000)
      context = %CastContext{caster_guid: 5, caster_level: 60, spell: vanish}
      {entity, _events} = SpellEffect.receive(entity, context, vanish, 2_000)

      refute Aura.has_aura?(entity, :mod_stalked)
    end
  end

  describe "combat buffs" do
    test "evasion and ghostly strike increase actual dodge resolution" do
      evasion = %Spell{
        id: 5277,
        duration_ms: 15_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_dodge, base_points: 50}]
      }

      attack = %{caster_level: 60, caster_player?: true, caster_attack_skill: 300, crit_chance: 0.0}
      assert AttackTable.resolve(rogue(), attack, 10, roll: 2_000).outcome == :normal

      {entity, _events} = Aura.apply_spell(rogue(), 5, 60, evasion, 1_000)
      assert AttackTable.resolve(entity, attack, 10, roll: 2_000).outcome == :dodge
    end

    test "sprint changes the authoritative movement speed" do
      sprint = %Spell{
        id: 2983,
        duration_ms: 15_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_increase_speed, base_points: 50}]
      }

      {entity, _events} = Aura.apply_spell(rogue(), 5, 60, sprint, 1_000)
      assert entity.movement_block.run_speed == 10.5
    end

    test "slice and dice changes the authoritative swing timer" do
      slice_and_dice = %Spell{
        id: 5171,
        duration_ms: 9_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_melee_haste, base_points: 20}]
      }

      entity = %{rogue() | unit: %{rogue().unit | base_attack_time: 2_000}}
      {entity, _events} = Aura.apply_spell(entity, 5, 60, slice_and_dice, 1_000)
      assert Combat.attack_speed_ms(entity) == 1_666
    end
  end
end
