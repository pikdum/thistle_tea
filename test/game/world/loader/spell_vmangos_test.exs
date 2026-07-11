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
    end

    test "feint, cold blood, and vanish load their rogue mechanics" do
      assert Enum.any?(SpellLoader.load(1966).effects, &(&1.type == :modify_threat))
      assert Enum.any?(SpellLoader.load(14_177).effects, &(&1.aura == :force_crit))
      assert Enum.any?(SpellLoader.load(1856).effects, &(&1.type == :clear_threat))
    end

    test "finishers load their per-combo-point scaling" do
      assert Enum.find(SpellLoader.load(11_300).effects, &(&1.type == :school_damage)).points_per_combo == 151.0
      assert Enum.find(SpellLoader.load(11_198).effects, &(&1.aura == :mod_resistance)).points_per_combo == -340.0
    end

    test "backstab and ambush load their behind-target requirement" do
      assert Spell.attribute?(SpellLoader.load(53), :from_behind)
      assert Spell.attribute?(SpellLoader.load(8676), :from_behind)
      assert Spell.attribute?(SpellLoader.load(1776), :target_facing_caster)
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
end
