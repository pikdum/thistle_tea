defmodule ThistleTea.Game.World.Loader.SpellCasterLocationDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell.CasterLocation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.LocationTargets
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "decodes all four directional Blink spells" do
      for {id, selector} <- [
            {29_208, :caster_front},
            {29_209, :caster_back},
            {29_210, :caster_left},
            {29_211, :caster_right}
          ] do
        spell = SpellLoader.load(id)

        assert %Effect{type: :leap, implicit_target_a: :caster, implicit_target_b: ^selector, radius_yards: 20.0} =
                 hd(spell.effects)

        assert LocationTargets.required?(spell)
      end

      refute LocationTargets.required?(SpellLoader.load(1953))
    end

    test "decodes compass summons and secondary destinations" do
      for {id, selector} <- [
            {26_144, :caster_front},
            {26_145, :caster_right},
            {26_146, :caster_back},
            {26_147, :caster_left},
            {26_148, :caster_front_right},
            {26_149, :caster_back_right},
            {26_150, :caster_back_left},
            {26_151, :caster_front_left}
          ] do
        assert [%Effect{type: :summon_wild, implicit_target_a: ^selector, radius_yards: 30.0}] =
                 SpellLoader.load(id).effects
      end

      assert [%Effect{type: :trans_door, implicit_target_a: :caster_front, radius_yards: 3.0}] =
               SpellLoader.load(10_059).effects

      assert [
               %Effect{
                 type: :trans_door,
                 implicit_target_a: :caster_source,
                 implicit_target_b: :caster_front,
                 radius_yards: 2.0
               }
             ] = SpellLoader.load(724).effects

      assert [%Effect{type: :summon_game_object, implicit_target_a: :caster_front, radius_yards: 2.0}] =
               SpellLoader.load(1499).effects
    end

    test "retains elemental slots while excluding duel flag placement" do
      for {id, slot, selector} <- [
            {3599, 1, :caster_front_left},
            {8071, 2, :caster_front_right},
            {5394, 3, :caster_back_right}
          ] do
        assert [%Effect{type: :summon_totem, summon_slot: ^slot, implicit_target_a: ^selector}] =
                 SpellLoader.load(id).effects
      end

      duel = SpellLoader.load(7266)
      refute LocationTargets.required?(duel)
      refute CasterLocation.required?(hd(duel.effects))
    end
  end
end
