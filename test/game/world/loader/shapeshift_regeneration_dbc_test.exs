defmodule ThistleTea.Game.World.Loader.ShapeshiftRegenerationDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Regen
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  setup [:druid]

  describe "tick/2" do
    test "recovers mana through cat, bear, and caster transitions", %{druid: druid} do
      for {spell_id, form, power_type} <- [{768, 1, 3}, {5487, 5, 1}, {9634, 8, 1}] do
        shifted = cast_aura(druid, spell_id, 1_000)
        assert shifted.unit.shapeshift_form == form
        assert shifted.unit.power_type == power_type
        assert shifted.unit.power1 == 1_450
        assert shifted.internal.last_mana_use_at == 1_000

        assert Regen.tick(shifted, 5_999).unit.power1 == 1_450
        shifted = Regen.tick(shifted, 6_000)
        assert shifted.unit.power1 == 1_473

        {restored, _events} = Aura.remove_spells(shifted, [spell_id], 6_001)
        assert restored.unit.power_type == 0
        assert restored.unit.shapeshift_form == 0
        assert restored.unit.power1 == 1_473
        assert Regen.tick(restored, 8_000).unit.power1 == 1_496
      end
    end

    test "keeps a two-second cadence after cat energy fills", %{druid: druid} do
      shifted = cast_aura(druid, 768, 1_000)
      tree = BT.action(fn entity, blackboard -> {:failure, entity, blackboard} end)

      shifted =
        Enum.reduce([3_000, 5_000, 7_000, 9_000, 11_000], shifted, fn now, entity ->
          assert {:failure, entity} = BehaviorRunner.tick(tree, entity, Context.new(now))
          entity
        end)

      assert shifted.unit.power4 == 100
      assert shifted.unit.power1 == 1_519
      assert Tick.player_delay(shifted, :success, 11_000) == 2_000

      assert {:failure, unchanged} = BehaviorRunner.tick(tree, shifted, Context.new(12_999))
      assert unchanged.unit.power1 == 1_519
      assert {:failure, recovered} = BehaviorRunner.tick(tree, shifted, Context.new(13_000))
      assert recovered.unit.power1 == 1_542
      assert recovered.unit.power4 == 100
    end

    test "applies Reflection and Innervate while shifted and restores rates on removal", %{druid: druid} do
      reflection = SpellLoader.load(17_108)
      innervate = SpellLoader.load(29_166)
      {druid, _events} = Aura.apply_spell(druid, 1, 60, reflection, 0)
      shifted = cast_aura(druid, 768, 1_000)

      assert Regen.tick(shifted, 3_000).unit.power1 == 1_453

      {boosted, _events} = Aura.apply_spell(shifted, 2, 60, innervate, 2_000)
      assert Regen.tick(boosted, 3_000).unit.power1 == 1_565

      {cancelled, _events} = Aura.remove_spells(boosted, [29_166], 3_001)
      assert Regen.tick(cancelled, 4_000).unit.power1 == 1_453

      {expired, _events} = Aura.tick(boosted, 2_000 + innervate.duration_ms)
      refute Aura.has_aura?(expired, :mod_power_regen_percent)
      assert Regen.tick(expired, 30_000).unit.power1 == 1_473
      assert expired.unit.power_type == 3
    end

    test "cleans up form and temporary recovery on death and resumes after resurrection", %{druid: druid} do
      shifted = cast_aura(druid, 768, 1_000)
      {shifted, _events} = Aura.apply_spell(shifted, 2, 60, SpellLoader.load(29_166), 2_000)
      dead = Core.take_damage(shifted, shifted.unit.health, 3_000)

      assert dead.unit.health == 0
      assert dead.unit.power_type == 0
      refute Aura.has_aura?(dead, :mod_shapeshift)
      refute Aura.has_aura?(dead, :mod_power_regen_percent)
      assert Regen.tick(dead, 10_000) == dead
      refute Regen.needs_regen?(dead)

      {restored, _events} = Death.resurrect(dead, 0.5, 10_000)
      mana = restored.unit.power1
      assert Regen.tick(restored, 12_000).unit.power1 == mana + 23
    end
  end

  defp cast_aura(druid, spell_id, now) do
    spell = SpellLoader.load(spell_id)
    druid = Resources.spend_power(druid, spell, now)
    {druid, _events} = Aura.apply_spell(druid, 1, 60, spell, now)
    druid
  end

  defp druid(_context) do
    unit =
      Stats.recompute(%Unit{
        class: 11,
        race: 4,
        level: 60,
        health: 1_220,
        base_health: 1_000,
        base_strength: 40,
        base_agility: 40,
        base_stamina: 40,
        base_intellect: 100,
        base_spirit: 40,
        base_mana: 1_000,
        power_type: 0,
        power1: 2_000,
        power2: 0,
        power4: 100,
        max_power4: 100,
        auras: []
      })

    {:ok,
     druid: %Character{
       object: %Object{guid: 1},
       unit: unit,
       player: %Player{},
       movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
       internal: %Internal{}
     }}
  end
end
