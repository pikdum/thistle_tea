defmodule ThistleTea.Game.World.Loader.SpellVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Logic.SpellBook
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.ClassSpell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellThreat

  @moduletag :dbc_db

  setup_all do
    :ok = SpellThreat.load_all()
  end

  describe "stance spells" do
    @describetag :dbc_db

    test "battle stance loads the form aura with its baked threat passive" do
      spell = SpellLoader.load(2457)

      assert %Spell{stances: 0} = spell

      assert %Effect{type: :apply_aura, aura: :mod_shapeshift, misc_value: 17} =
               Enum.find(spell.effects, &(&1.aura == :mod_shapeshift))

      assert %Effect{type: :apply_aura, aura: :mod_threat} =
               Enum.find(spell.effects, &(&1.aura == :mod_threat))
    end

    test "defensive stance bakes damage and threat passives" do
      spell = SpellLoader.load(71)

      auras = Enum.map(spell.effects, & &1.aura)

      assert :mod_shapeshift in auras
      assert :mod_threat in auras
      assert :mod_damage_percent_taken in auras or 87 in auras
    end
  end

  describe "stance-locked abilities" do
    @describetag :dbc_db

    test "overpower requires battle stance" do
      spell = SpellLoader.load(7384)

      assert spell.stances == 0x10000
      assert Spell.usable_in_stance?(spell, 17)
      refute Spell.usable_in_stance?(spell, 19)
    end

    test "whirlwind requires berserker stance" do
      spell = SpellLoader.load(1680)

      assert spell.stances == 0x40000
    end
  end

  describe "spell threat" do
    alias SpellThreat, as: SpellThreatLoader

    test "heroic strike carries flat bonus threat" do
      assert %{threat: 20.0, multiplier: 1.0} = SpellThreatLoader.get(78)
    end

    test "revenge carries a threat multiplier" do
      assert %{threat: 63.0, multiplier: 2.25} = SpellThreatLoader.get(6572)
    end

    test "spells without entries return nil" do
      assert SpellThreatLoader.get(133) == nil
    end
  end

  describe "sunder armor" do
    @describetag :dbc_db

    test "loads its stack cap" do
      spell = SpellLoader.load(7386)

      assert spell.stack_amount == 5
    end
  end

  describe "talent grants" do
    alias ClassSpell, as: ClassSpellLoader

    @describetag :dbc_db

    test "warrior debug spells include non-passive talent actives" do
      spell_ids = ClassSpellLoader.trainable_spell_ids(1, 60)

      assert 12_294 in spell_ids
      assert 23_881 in spell_ids
      assert 12_975 in spell_ids
      assert 12_323 in spell_ids
    end

    test "passive talents stay out of the grant list" do
      spell_ids = ClassSpellLoader.trainable_spell_ids(1, 60)

      refute 12_320 in spell_ids
    end
  end

  describe "warrior spell parsing" do
    @describetag :dbc_db

    test "heroic strike is an on-next-swing melee ability with a rage refund on avoid" do
      spell = SpellLoader.load(78)

      assert Spell.attribute?(spell, :on_next_swing)
      assert Spell.attribute?(spell, :discount_power_on_miss)
      assert spell.dmg_class == 2
    end

    test "bloodrage costs a percentage of base health" do
      spell = SpellLoader.load(2687)

      assert spell.power_type == -2
      assert spell.mana_cost_percent == 20
      assert Enum.any?(spell.effects, &(&1.type == :energize))
    end
  end

  describe "spell critical parsing" do
    test "loads flat and school-specific spell crit auras" do
      assert Enum.any?(SpellLoader.load(2916).effects, &(&1.aura == :mod_spell_crit_chance))
      assert Enum.any?(SpellLoader.load(5835).effects, &(&1.aura == :mod_spell_crit_chance_school))
    end

    test "loads the cannot-crit attribute" do
      assert Spell.attribute?(SpellLoader.load(5857), :cant_crit)
    end
  end

  describe "warrior spell acquisition" do
    @describetag :dbc_db

    test "keeps only the highest superseding rank regardless of spell id order" do
      initial_ids = [6673, 7386]
      trainable_ids = ClassSpell.trainable_spell_ids(1, 60)
      superseded_by = SpellLoader.superseded_by_map(initial_ids ++ trainable_ids)

      {known_ids, _events} = SpellBook.learn(initial_ids, trainable_ids, superseded_by)

      refute Enum.any?(superseded_by, fn {old_id, new_id} -> old_id in known_ids and new_id in known_ids end)
      assert 11_551 in known_ids
      assert 11_597 in known_ids
      refute 6673 in known_ids
      refute 7386 in known_ids
    end
  end

  describe "rogue spell parsing" do
    test "combo builders and stealth use semantic effect names" do
      sinister_strike = SpellLoader.load(1757)
      stealth = SpellLoader.load(1784)

      assert Enum.any?(sinister_strike.effects, &(&1.type == :add_combo_points))
      assert Enum.any?(stealth.effects, &(&1.aura == :mod_stealth))
      assert stealth.stances == 0
      assert Spell.attribute?(stealth, :not_in_combat)
    end

    test "feint, cold blood, and vanish load their rogue mechanics" do
      assert Enum.any?(SpellLoader.load(1966).effects, &(&1.type == :modify_threat))
      assert Enum.any?(SpellLoader.load(14_177).effects, &(&1.aura == :force_crit))
      assert Enum.any?(SpellLoader.load(1856).effects, &(&1.type == :clear_threat))
    end

    test "blade flurry loads its melee proc mask" do
      blade_flurry = SpellLoader.load(13_877)

      assert Spell.procs_on?(blade_flurry, :deal_melee_swing)
      assert Spell.procs_on?(blade_flurry, :deal_melee_ability)
    end

    test "finishers load their per-combo-point scaling" do
      assert Enum.find(SpellLoader.load(11_300).effects, &(&1.type == :school_damage)).points_per_combo == 151.0
      assert Enum.find(SpellLoader.load(11_198).effects, &(&1.aura == :mod_resistance)).points_per_combo == -340.0
      assert %Spell{duration_ms: 6_000, max_duration_ms: 16_000} = SpellLoader.load(1943)
      assert %Spell{duration_ms: 0, max_duration_ms: 5_000} = SpellLoader.load(408)
    end

    test "backstab and ambush load their behind-target requirement" do
      assert Spell.attribute?(SpellLoader.load(53), :from_behind)
      assert Spell.attribute?(SpellLoader.load(8676), :from_behind)
      assert Spell.attribute?(SpellLoader.load(1776), :target_facing_caster)
    end

    test "stealth and cold blood start cooldowns when their auras end" do
      assert Spell.attribute?(SpellLoader.load(1784), :cooldown_on_event)
      assert Spell.attribute?(SpellLoader.load(14_177), :cooldown_on_event)
    end

    test "vanish triggers stealth and movement-impairing purge spells" do
      vanish = SpellLoader.load(1856)

      assert Enum.any?(vanish.effects, &(&1.type == :trigger_spell and &1.trigger_spell_id == 11_327))
      assert Enum.any?(vanish.effects, &(&1.type == :trigger_spell and &1.trigger_spell_id == 18_461))
    end

    test "debug rogue spells include active talents but exclude passives" do
      spell_ids = ClassSpell.trainable_spell_ids(4, 60)

      assert 13_750 in spell_ids
      assert 13_877 in spell_ids
      assert 14_177 in spell_ids
      assert 14_185 in spell_ids
      refute 14_056 in spell_ids
    end
  end

  describe "melee spell avoidance parsing" do
    test "only spells marked completely blockable load the block attribute" do
      assert Spell.attribute?(SpellLoader.load(72), :completely_blocked)
      refute Spell.attribute?(SpellLoader.load(20_467), :completely_blocked)
      refute Spell.attribute?(SpellLoader.load(20_424), :completely_blocked)
    end
  end

  describe "paladin spell parsing" do
    test "seals encode exclusive ownership and their judgement spell" do
      seal = SpellLoader.load(20_287)

      assert seal.exclusive_category == :paladin_seal
      assert %Effect{index: 2, aura: :dummy, base_points: 20_279} = Enum.find(seal.effects, &(&1.index == 2))
      refute Spell.attribute?(SpellLoader.load(20_271), :from_behind)
    end

    test "blessings and auras load their exclusive categories" do
      assert SpellLoader.load(19_740).exclusive_category == :paladin_blessing
      assert SpellLoader.load(465).exclusive_category == :paladin_aura
      assert Enum.any?(SpellLoader.load(465).effects, &(&1.type == :apply_area_aura))
    end

    test "scripted Paladin mechanics retain their identifying DBC data" do
      assert %Spell{spell_family: 10, spell_icon: 561} = SpellLoader.load(20_425)
      assert %Spell{spell_family: 0, spell_icon: 561} = SpellLoader.load(20_424)
      assert Spell.family_flag?(SpellLoader.load(19_977), 10, 0x10000000)
      assert Spell.family_flag?(SpellLoader.load(639), 10, 0x80000000)
      assert Spell.family_flag?(SpellLoader.load(19_750), 10, 0x40000000)
      assert Spell.family_flag?(SpellLoader.load(20_375), 10, 0x02000000)
    end

    test "defensive and stat blessings load semantic aura types" do
      assert Enum.any?(SpellLoader.load(642).effects, &(&1.aura == :school_immunity))
      assert Enum.any?(SpellLoader.load(20_217).effects, &(&1.aura == :mod_total_stat_percent))
      assert Enum.any?(SpellLoader.load(20_911).effects, &(&1.aura == :damage_shield))
    end

    test "creature-family restrictions come from the DBC mask" do
      assert SpellLoader.load(879).target_creature_type_mask == 36
      assert SpellLoader.load(2812).target_creature_type_mask == 36
      assert SpellLoader.load(2878).target_creature_type_mask == 32
    end

    test "Lay on Hands loads heal-to-full and paladin debug spells include active talents" do
      assert Enum.any?(SpellLoader.load(633).effects, &(&1.type == :heal_max_health))
      assert Enum.any?(SpellLoader.load(639).effects, &(&1.type == :heal))
      assert Enum.any?(SpellLoader.load(19_750).effects, &(&1.type == :heal))

      spell_ids = ClassSpell.trainable_spell_ids(2, 60)
      assert 20_066 in spell_ids
      assert 20_473 in spell_ids
      assert 20_375 in spell_ids
    end
  end

  describe "warlock spell parsing" do
    test "demon summons load as caster-targeted pet effects" do
      assert %Effect{type: :summon_pet, misc_value: 416, implicit_target_a: :caster} =
               Enum.find(SpellLoader.load(688).effects, &(&1.type == :summon_pet))

      assert %Effect{type: :summon_pet, misc_value: 1860} =
               Enum.find(SpellLoader.load(697).effects, &(&1.type == :summon_pet))
    end

    test "drains load their distinct health and mana semantics" do
      assert Enum.any?(SpellLoader.load(6789).effects, &(&1.type == :health_leech))
      assert Enum.any?(SpellLoader.load(5138).effects, &(&1.aura == :periodic_mana_leech))
      assert Enum.any?(SpellLoader.load(18_220).effects, &(&1.type == :power_drain and &1.implicit_target_a == :pet))
    end

    test "Health Funnel loads its initial and per-second health costs" do
      spell = SpellLoader.load(11_693)

      assert spell.power_type == -2
      assert spell.mana_cost == 45
      assert spell.mana_cost_per_second == 33
    end

    test "scripted warlock ranks share DBC family flags" do
      assert Spell.family_flag?(SpellLoader.load(1454), 5, 0x00040000)
      assert Spell.family_flag?(SpellLoader.load(11_689), 5, 0x00040000)
      assert Spell.family_flag?(SpellLoader.load(17_962), 5, 0x00000200)
      assert Spell.family_flag?(SpellLoader.load(348), 5, 0x00000004)
      assert Spell.family_flag?(SpellLoader.load(980), 5, 0x00000400)
    end

    test "curses share per-caster exclusive ownership" do
      assert SpellLoader.load(702).exclusive_category == :warlock_curse
      assert SpellLoader.load(980).exclusive_category == :warlock_curse
      assert SpellLoader.load(1490).exclusive_category == :warlock_curse
      assert SpellLoader.load(18_223).exclusive_category == :warlock_curse
      assert Enum.any?(SpellLoader.load(1714).effects, &(&1.aura == :mod_casting_speed))
    end

    test "Soul Link loads its pet target and percentage redirect aura" do
      assert Enum.any?(SpellLoader.load(19_028).effects, &(&1.type == :dummy and &1.implicit_target_a == :pet))

      assert Enum.any?(SpellLoader.load(25_228).effects, fn effect ->
               effect.type == :apply_area_aura and effect.aura == :split_damage_percent
             end)
    end

    test "debug Warlocks learn quest demons alongside trainer and talent spells" do
      spell_ids = ClassSpell.trainable_spell_ids(9, 60)

      assert 688 in spell_ids
      assert 697 in spell_ids
      assert 712 in spell_ids
      assert 691 in spell_ids
      assert 1122 in spell_ids
      assert 18_540 in spell_ids
      assert 18_288 in spell_ids
    end
  end

  describe "hunter, shaman, and druid spell parsing" do
    test "loads trap, totem, ranged haste, and form semantics" do
      assert Enum.any?(SpellLoader.load(1499).effects, &(&1.type == :summon_game_object and &1.misc_value == 2561))

      assert %Effect{type: :summon_totem, summon_slot: 1, misc_value: 2523} =
               Enum.find(SpellLoader.load(3599).effects, &(&1.type == :summon_totem))

      assert Enum.any?(SpellLoader.load(29_414).effects, &(&1.aura == :mod_ranged_haste))
      assert SpellLoader.load(768).exclusive_category == :shapeshift
      assert SpellLoader.load(13_163).exclusive_category == :hunter_aspect
      assert SpellLoader.load(13_161).exclusive_category == :hunter_aspect
      assert SpellLoader.load(1494).exclusive_category == :tracking
      assert SpellLoader.load(324).exclusive_category == :shaman_shield
    end

    test "debug spellbooks include quest and talent actives" do
      hunter = ClassSpell.trainable_spell_ids(3, 60)
      shaman = ClassSpell.trainable_spell_ids(7, 60)
      druid = ClassSpell.trainable_spell_ids(11, 60)

      assert Enum.all?([1515, 883, 982, 136], &(&1 in hunter))
      assert Enum.all?([8071, 3599, 5394, 8512], &(&1 in shaman))
      assert Enum.all?([5487, 1066, 768], &(&1 in druid))
    end
  end
end
