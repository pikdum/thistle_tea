defmodule ThistleTea.Game.World.Loader.SpellUnitTargetDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos.SpellEffectMod
  alias ThistleTea.Game.Spell.Effect
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
