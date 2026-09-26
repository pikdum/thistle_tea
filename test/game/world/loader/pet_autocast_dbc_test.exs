defmodule ThistleTea.Game.World.Loader.PetAutocastDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet.Autocast
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  describe "load/1" do
    test "every pet Fire Shield and Devour Magic rank retains its selectable recipients" do
      for id <- [2_947, 8_316, 8_317, 11_770, 11_771] do
        spell = SpellLoader.load(id)
        assert SpellTarget.target_query(spell, Target.unit(42)) == {:party_unit, 42}
        refute Spell.harmful?(spell)
        assert spell.spell_visual == 289
        assert Spell.family_flag?(spell, 5, 0x00800000)
        assert spell.range_yards == 30.0
      end

      for id <- [19_505, 19_731, 19_734, 19_736] do
        spell = SpellLoader.load(id)
        assert SpellTarget.target_query(spell, Target.unit(42)) == {:unit, 42}
        assert [%{type: :dispel, implicit_target_a: :any_unit, misc_value: 1}] = spell.effects
        refute Spell.harmful?(spell)
      end
    end

    test "Dash and Dive wait for combat and do not fire within melee reach" do
      for id <- [23_099, 23_109, 23_110, 23_145, 23_147, 23_148] do
        spell = SpellLoader.load(id)
        idle = pet(id)
        attacking = %{idle | unit: %{idle.unit | target: 2}}
        refute Autocast.allowed?(idle, spell, 1, context(20.0))
        assert Autocast.allowed?(attacking, spell, 1, context(20.0))
        refute Autocast.allowed?(attacking, spell, 1, context(2.0))
      end
    end

    test "Furious Howl and Tainted Blood wait for a victim while Prowl preserves an attack command" do
      for id <- [24_604, 19_478] do
        spell = SpellLoader.load(id)
        idle = pet(id)
        refute Autocast.allowed?(idle, spell, 1, context(20.0))
        assert Autocast.allowed?(%{idle | unit: %{idle.unit | target: 2}}, spell, 1, context(20.0))
      end

      spell = SpellLoader.load(24_450)
      idle = pet(spell.id)
      assert Autocast.allowed?(idle, spell, 1, context(20.0))
      refute Autocast.allowed?(%{idle | unit: %{idle.unit | target: 2}}, spell, 1, context(20.0))
    end
  end

  defp pet(id) do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, auras: [], combat_reach: 1.5},
      internal: %Internal{pet: %Internal.Pet{kind: :hunter, autocast: MapSet.new([id])}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp context(distance) do
    world = WorldRef.open(0)
    target = %Observation{guid: 2, position: {world, distance, 0.0, 0.0}, distance: distance, metadata: %{}}
    perception = Perception.new(1_000, {world, 0.0, 0.0, 0.0}, %{2 => target}, %{})
    Context.new(1_000, perception: perception)
  end
end
