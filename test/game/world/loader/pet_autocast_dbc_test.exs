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
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  describe "load/1" do
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
