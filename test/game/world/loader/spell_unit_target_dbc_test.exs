defmodule ThistleTea.Game.World.Loader.SpellUnitTargetDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos.SpellEffectMod
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.LocationTargets
  alias ThistleTea.Game.Spell.UnitTargets
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db

  setup do
    key = {:mods, 11_513}
    previous = :ets.lookup(SpellEffectOverride, key)

    override = %SpellEffectMod{
      id: 11_513,
      effect_index: 0,
      effect: 77,
      effect_implicit_target_a: 38,
      effect_implicit_target_b: 1,
      effect_misc_value: 0
    }

    :ets.insert(SpellEffectOverride, {key, %{0 => override}})

    on_exit(fn ->
      :ets.delete(SpellEffectOverride, key)
      :ets.insert(SpellEffectOverride, previous)
    end)

    :ok
  end

  describe "load/1" do
    test "distinguishes selected-unit positions from area selectors" do
      summon = SpellLoader.load(22_421)
      assert [%Effect{type: :summon_wild, implicit_target_a: :enemy_location, area_target?: false}] = summon.effects
      assert LocationTargets.required?(summon)

      assert [%Effect{implicit_target_a: :enemy_location, implicit_target_b: :aoe_enemy_at_dest, area_target?: true}] =
               SpellLoader.load(26_789).effects

      assert [%Effect{type: :teleport_units, implicit_target_a: :caster, implicit_target_b: :unit_location}] =
               SpellLoader.load(28_401).effects
    end

    test "decodes database locations for summons, ground auras and teleports" do
      for {id, type} <- [{18_634, :summon_guardian}, {29_237, :summon_wild}, {22_191, :persistent_area_aura}] do
        spell = SpellLoader.load(id)
        assert %Effect{type: ^type, implicit_target_a: :database_location} = hd(spell.effects)
        assert LocationTargets.required?(spell)
      end

      teleport = SpellLoader.load(3561)
      assert %Effect{type: :teleport_units, implicit_target_b: :database_location} = hd(teleport.effects)
      refute LocationTargets.required?(teleport)
    end

    test "decodes creature, corpse and object destination spells" do
      for id <- [9082, 12_699, 26_286, 26_344] do
        assert LocationTargets.required?(SpellLoader.load(id))
      end

      assert hd(SpellLoader.load(12_699).effects).implicit_target_b == :script_location_near_caster
      assert hd(SpellLoader.load(9082).effects).implicit_target_a == :script_location_near_caster
    end

    test "decodes scripted areas and marks scripted cones as area effects" do
      assert UnitTargets.area?(SpellLoader.load(5628))
      assert UnitTargets.area?(SpellLoader.load(26_393))
      cannon = SpellLoader.load(24_933)
      assert UnitTargets.area?(cannon)
      assert Enum.all?(cannon.effects, & &1.area_target?)
      assert hd(cannon.effects).implicit_target_a == :script_units_in_cone
    end

    test "decodes nearest-creature selection while retaining caster and mixed effects" do
      phial = SpellLoader.load(11_513)

      assert [
               %Effect{
                 type: :script_effect,
                 item_type: 9284,
                 implicit_target_a: :creature_near_caster,
                 implicit_target_b: :caster
               }
             ] = phial.effects

      assert UnitTargets.required?(phial)

      assert [%Effect{implicit_target_a: :creature_near_caster}, %Effect{implicit_target_a: :caster}] =
               SpellLoader.load(7393).effects

      assert UnitTargets.required?(SpellLoader.load(8593))
    end
  end
end
