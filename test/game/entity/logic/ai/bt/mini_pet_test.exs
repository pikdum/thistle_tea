defmodule ThistleTea.Game.Entity.Logic.AI.BT.MiniPetTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.MiniPet
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.WorldRef

  setup [:pet]

  describe "tick/3" do
    test "follows behind its owner without combat actions", %{pet: pet} do
      observation = owner()
      context = context(pet, observation)
      assert {{:running, _}, moved, _} = MiniPet.tick(pet, %Blackboard{}, context)
      assert [%NavigationIntent{destination: {x, y, z}}] = moved.internal.navigation_intents
      assert_in_delta x, 8.0, 0.001
      assert_in_delta y, 0.0, 0.001
      assert z == 0.0
      refute Enum.any?(moved.internal.events, &is_struct(&1, Effects.AttackStart))
      refute moved.internal.in_combat
    end

    test "removes itself for missing dead distant or other-world owners", %{pet: pet} do
      for observation <- [
            nil,
            %{owner() | metadata: %{alive?: false}},
            %{owner() | distance: 120.1},
            %{owner() | position: {WorldRef.open(1), 10.0, 0.0, 0.0}}
          ] do
        assert {:success, removed, _} = MiniPet.tick(pet, %Blackboard{}, context(pet, observation))
        assert [%Effects.DespawnSelf{}] = removed.internal.events
        assert removed.internal.navigation_intents == []
      end
    end
  end

  defp pet(_context) do
    %{
      pet: %Mob{
        object: %Object{guid: 2},
        unit: %Unit{health: 5, bounding_radius: 0.25},
        internal: %Internal{world: WorldRef.open(0), in_combat: false, pet: %Pet{owner_guid: 1, kind: :mini_pet}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, run_speed: 7.0}
      }
    }
  end

  defp owner do
    %Observation{
      guid: 1,
      position: {WorldRef.open(0), 10.0, 0.0, 0.0},
      grounded_position: {WorldRef.open(0), 10.0, 0.0, 0.0},
      distance: 10.0,
      metadata: %{alive?: true, orientation: 0.0}
    }
  end

  defp context(pet, observation) do
    entities = if observation, do: %{1 => observation}, else: %{}

    perception =
      Perception.new(1000, {pet.internal.world, 0.0, 0.0, 0.0}, entities, %{mobs: [], players: [], game_objects: []})

    Context.new(1000, perception: perception)
  end
end
