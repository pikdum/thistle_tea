defmodule ThistleTea.Game.Entity.Data.Component.Internal.WaypointRouteTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Waypoint
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute

  describe "build/1" do
    test "returns nil for empty creature movement" do
      creature = %Creature{creature_movement: []}
      assert WaypointRoute.build(creature) == nil
    end

    test "returns nil for nil creature movement" do
      creature = %Creature{creature_movement: nil}
      assert WaypointRoute.build(creature) == nil
    end
  end

  describe "destination_waypoint/1" do
    test "returns waypoint by destination_point id" do
      waypoint = %Waypoint{position: {1.0, 2.0, 3.0, 0.5}, wait_time: 100}
      route = %WaypointRoute{destination_point: 1, points: %{1 => waypoint}}
      assert WaypointRoute.destination_waypoint(route) == waypoint
    end

    test "returns nil for non-existent point" do
      route = %WaypointRoute{destination_point: 99, points: %{}}
      assert WaypointRoute.destination_waypoint(route) == nil
    end
  end

  describe "increment_waypoint/1" do
    test "increments to next waypoint" do
      route = %WaypointRoute{
        first_point: 1,
        destination_point: 1,
        points: %{1 => %Waypoint{}, 2 => %Waypoint{}, 3 => %Waypoint{}}
      }

      result = WaypointRoute.increment_waypoint(route)
      assert result.destination_point == 2
    end

    test "wraps to first_point when at end" do
      route = %WaypointRoute{
        first_point: 1,
        destination_point: 3,
        points: %{1 => %Waypoint{}, 2 => %Waypoint{}, 3 => %Waypoint{}}
      }

      result = WaypointRoute.increment_waypoint(route)
      assert result.destination_point == 1
    end

    test "wraps when next point does not exist" do
      route = %WaypointRoute{
        first_point: 1,
        destination_point: 2,
        points: %{1 => %Waypoint{}, 2 => %Waypoint{}}
      }

      result = WaypointRoute.increment_waypoint(route)
      assert result.destination_point == 1
    end

    test "preserves other route fields" do
      route = %WaypointRoute{
        first_point: 1,
        destination_point: 1,
        points: %{1 => %Waypoint{}}
      }

      result = WaypointRoute.increment_waypoint(route)
      assert result.first_point == 1
      assert result.points == route.points
    end
  end
end
