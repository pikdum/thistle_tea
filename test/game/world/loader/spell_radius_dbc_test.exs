defmodule ThistleTea.Game.World.Loader.SpellRadiusDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Radius
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride

  @moduletag :dbc_db

  setup [:totemic_mastery_mask]

  describe "load/1" do
    test "vanilla talents select the intended spell radii" do
      caster = %Mob{object: %Object{guid: 1}, unit: %Unit{level: 60, auras: []}, internal: %Internal{}}

      for {talent_id, spell_id, radius} <- [
            {16_758, 122, 12.0},
            {12_838, 6673, 30.0},
            {16_189, 8076, 30.0},
            {21_895, 8076, 30.0},
            {23_549, 2120, 6.25},
            {27_790, 15_237, 12.0}
          ] do
        talent = SpellLoader.load(talent_id)
        {modified, _events} = Aura.apply_spell(caster, 1, 60, talent, 0)
        spell = SpellLoader.load(spell_id)
        modifiers = Modifiers.snapshot(modified, spell)
        assert Radius.maximum(spell.effects, modifiers) == radius, "#{talent.name}: #{spell.name}"

        if spell_id == 122 do
          assert SpellTarget.target_query(spell, Target.none(), modifiers) == {:caster_aoe, 12.0}
        end
      end
    end
  end

  defp totemic_mastery_mask(_context) do
    key = {:class_masks, 16_189}
    previous = :ets.lookup(SpellEffectOverride, key)
    :ets.insert(SpellEffectOverride, {key, {67_624_960, 0, 0}})

    on_exit(fn ->
      :ets.delete(SpellEffectOverride, key)
      :ets.insert(SpellEffectOverride, previous)
    end)

    :ok
  end
end
