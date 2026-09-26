defmodule ThistleTea.Game.World.Loader.SpellCombatControlDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CastingCombat
  alias ThistleTea.Game.Entity.Logic.Charge
  alias ThistleTea.Game.Entity.Logic.CombatControl
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "ordinary casts and instant combat spells reset swings while exempt shots do not" do
      blackboard = Blackboard.new() |> Blackboard.put_next_at(:next_attack_at, 250, 1_000)
      entity = %Mob{unit: %Unit{base_attack_time: 2_400}, internal: %Internal{blackboard: blackboard}}

      for id <- [133, 635, 118, 122, 20_066] do
        spell = SpellLoader.load(id)
        launched = CastingCombat.launch(entity, Cast.new(spell, Target.none(), 1_000), 2_000)
        assert launched.internal.blackboard.combat.next_attack_at == 4_400
      end

      for id <- [19_434, 19_503] do
        spell = SpellLoader.load(id)
        assert Spell.attribute?(spell, :do_not_reset_combat_timers)
        assert CastingCombat.launch(entity, Cast.new(spell, Target.none(), 1_000), 2_000) == entity
      end
    end

    test "control spells and Vanish stop autoattack through their explicit attribute" do
      for id <- [118, 1_776, 2_094, 1_856, 20_066, 19_503] do
        assert Spell.attribute?(SpellLoader.load(id), :cancels_auto_attack_combat)
      end

      for id <- [122, 339, 5_782, 635, 1_752, 2_098] do
        refute Spell.attribute?(SpellLoader.load(id), :cancels_auto_attack_combat)
      end
    end

    test "charge spells retain their automatic attack and cancellation rules" do
      for id <- [100, 6_178, 11_578, 20_252, 13_119] do
        spell = SpellLoader.load(id)
        assert Enum.any?(spell.effects, &(&1.type == :charge))
        assert Charge.attack_on_arrival?(spell)
      end

      for id <- [13_711, 22_641] do
        spell = SpellLoader.load(id)
        assert Enum.any?(spell.effects, &(&1.type == :charge))
        assert Spell.attribute?(spell, :cancels_auto_attack_combat)
        refute Charge.attack_on_arrival?(spell)
      end
    end

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
