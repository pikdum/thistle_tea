defmodule ThistleTea.Game.World.PositionTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.WorldRef

  describe "put/2" do
    test "reconciles a mob's stationary and projected positions" do
      guid = Guid.from_low_guid(:mob, 1, unique_guid())
      moving = mob(guid)
      world = WorldRef.open(0)
      on_exit(fn -> World.remove_position(moving) end)

      World.update_position(moving)

      assert Position.projection(guid) ==
               {world, {0.0, 0.0, 0.0}, [{10.0, 0.0, 0.0}], 1_000, 1_000}

      assert World.position(guid, 1_500) == {WorldRef.open(0), 5.0, 0.0, 0.0}

      stopped = stop_at(moving, {5.0, 0.0, 0.0, 0.0})
      World.update_position(stopped)

      assert Position.projection(guid) == nil
      assert World.position(guid, 1_500) == {WorldRef.open(0), 5.0, 0.0, 0.0}
    end

    test "reconciles a character's server movement through the same funnel" do
      guid = Guid.from_low_guid(:player, unique_guid())
      moving = struct(Character, Map.from_struct(mob(guid)))
      on_exit(fn -> World.remove_position(moving) end)

      World.update_position(moving)
      assert Position.projection(guid)

      stopped = stop_at(moving, {5.0, 0.0, 0.0, 0.0})
      World.update_position(stopped)

      assert Position.projection(guid) == nil
      assert World.position(guid, 1_500) == {WorldRef.open(0), 5.0, 0.0, 0.0}
    end
  end

  describe "distance_between/3" do
    test "uses projected positions for both guid operands" do
      source_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())
      source = mob(source_guid)

      target = %{
        mob(target_guid)
        | movement_block: %{mob(target_guid).movement_block | position: {20.0, 0.0, 0.0, 0.0}}
      }

      on_exit(fn ->
        World.remove_position(source)
        World.remove_position(target)
      end)

      World.update_position(source)
      World.update_position(target)

      assert World.distance_between(source_guid, target_guid, 1_500) == 0.0
      assert World.distance_between(source, target_guid, 1_500) == 0.0
    end
  end

  defp mob(guid) do
    %Mob{
      object: %Object{guid: guid},
      internal: %Internal{
        world: WorldRef.open(0),
        movement_start_time: 1_000,
        movement_start_position: {0.0, 0.0, 0.0}
      },
      movement_block: %MovementBlock{
        position: {0.0, 0.0, 0.0, 0.0},
        spline_nodes: [{10.0, 0.0, 0.0}],
        duration: 1_000
      }
    }
  end

  defp stop_at(entity, position) do
    %{
      entity
      | internal: %{entity.internal | movement_start_time: nil, movement_start_position: nil},
        movement_block: %{entity.movement_block | position: position, spline_nodes: [], duration: 0}
    }
  end

  defp unique_guid, do: System.unique_integer([:positive, :monotonic])
end
