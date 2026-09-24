defmodule ThistleTea.Game.World.Loader.SpellCombatControlDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CombatControl
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "area charm retains the vanilla spell-specific activation rule" do
      for id <- [26_740, 28_225, 28_410] do
        spell = SpellLoader.load(id)
        assert Enum.any?(spell.effects, &(&1.aura == :aoe_charm))
        assert Enum.any?(spell.effects, &Spell.charm_effect?(spell, &1)) == (id == 28_410)
      end
    end

    test "instant kills distinguish Death Touch from Suicide and positive sacrifice overrides" do
      assert Spell.starts_combat?(SpellLoader.load(5))
      refute Spell.harmful?(SpellLoader.load(7))
      sacrifice = SpellLoader.load(18_788)
      refute Spell.harmful?(%{sacrifice | custom_flags: 4})
    end

    test "Wisp Costume and Web Wrap load combined control" do
      for id <- [24_740, 28_618, 28_619, 28_620, 28_621] do
        spell = SpellLoader.load(id)
        assert Enum.any?(spell.effects, &(&1.aura == :mod_pacify_silence))
        entity = %{object: %Object{guid: 1}, unit: %Unit{auras: []}}
        {entity, _} = Aura.apply_spell(entity, 1, 50, spell, 0)
        assert CombatControl.pacified?(entity)
        assert CombatControl.silenced?(entity)
      end
    end

    test "Wisp Costume cancellation removes transformation and both controls" do
      spell = SpellLoader.load(24_740)
      entity = %{object: %Object{guid: 1}, unit: %Unit{auras: [], display_id: 49, native_display_id: 49}}
      {entity, _} = Aura.apply_spell(entity, 1, 50, spell, 0)
      assert entity.unit.display_id == 10_045
      {entity, _} = Aura.cancel_spell(entity, spell.id, 100)
      assert entity.unit.display_id == 49
      refute CombatControl.pacified?(entity)
      refute CombatControl.silenced?(entity)
    end
  end
end
