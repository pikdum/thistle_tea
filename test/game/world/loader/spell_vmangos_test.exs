defmodule ThistleTea.Game.World.Loader.SpellVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :vmangos_db

  describe "stance spells" do
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

  describe "warrior spell parsing" do
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
end
