defmodule ThistleTea.Game.World.PositionTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.Position.ClientMotion
  alias ThistleTea.Game.World.Position.Spline
  alias ThistleTea.Game.WorldRef

  describe "put/2" do
    test "reconciles a mob's stationary and projected positions" do
      guid = Guid.from_low_guid(:mob, 1, unique_guid())
      moving = mob(guid)
      world = WorldRef.open(0)
      on_exit(fn -> World.remove_position(moving) end)

      World.update_position(moving)

      assert Position.projection(guid) ==
               %Spline{
                 world: world,
                 origin: {0.0, 0.0, 0.0},
                 nodes: [{10.0, 0.0, 0.0}],
                 started_at: 1_000,
                 duration_ms: 1_000
               }

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

  describe "put/3" do
    test "projects bounded client motion and settles at its expiry" do
      guid = Guid.from_low_guid(:player, unique_guid())
      character = struct(Character, Map.from_struct(stop_at(mob(guid), {0.0, 0.0, 0.0, 0.0})))
      projection = Position.client_motion(character, {70.0, 0.0, 0.0}, 1_000, 750)
      on_exit(fn -> World.remove_position(character) end)

      Position.put(character, :players, projection)

      assert %ClientMotion{} = Position.projection(guid)
      assert World.position(guid, 1_100) == {WorldRef.open(0), 7.0, 0.0, 0.0}
      assert World.position(guid, 2_000) == {WorldRef.open(0), 52.5, 0.0, 0.0}

      assert World.snapshot_position(character, 1_100).movement_block.position ==
               {7.0, 0.0, 0.0, 0.0}

      assert Position.moving?(guid, 1_500)
      refute Position.moving?(guid, 2_000)

      Position.put(character, :players, nil)
      assert Position.projection(guid) == nil
      assert World.position(guid, 2_000) == {WorldRef.open(0), 0.0, 0.0, 0.0}
    end

    test "materializes client motion before an authoritative stop" do
      guid = Guid.from_low_guid(:player, unique_guid())
      now = System.monotonic_time(:millisecond)

      character =
        mob(guid)
        |> stop_at({0.0, 0.0, 0.0, 0.0})
        |> then(&%{&1 | movement_block: %{&1.movement_block | movement_flags: 1}})
        |> then(&struct(Character, Map.from_struct(&1)))

      projection = Position.client_motion(character, {70.0, 0.0, 0.0}, now - 100, 750)
      on_exit(fn -> World.remove_position(character) end)
      Position.put(character, :players, projection)

      stopped = character |> Movement.stop(now) |> EventSink.emit_pending()
      {x, y, z, orientation} = stopped.movement_block.position

      assert_in_delta x, 7.0, 1.0
      assert {y, z, orientation} == {0.0, 0.0, 0.0}
      assert Position.projection(guid) == nil
    end

    test "bounds client projection drift to the spatial broad-phase margin" do
      character = struct(Character, Map.from_struct(stop_at(mob(77), {0.0, 0.0, 0.0, 0.0})))

      assert %ClientMotion{started_at: 1_000, expires_at: expires_at} =
               Position.client_motion(character, {1_000.0, 0.0, 0.0}, 1_000, 750)

      assert expires_at < 1_750
      assert_in_delta expires_at, 1_176, 1
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

    test "exact queries do not discard projected vertical movement by its stale distance" do
      guid = Guid.from_low_guid(:mob, 1, unique_guid())

      moving = %{
        mob(guid)
        | internal: %{
            mob(guid).internal
            | movement_start_position: {0.0, 0.0, 1_000.0}
          },
          movement_block: %{
            mob(guid).movement_block
            | position: {0.0, 0.0, 1_000.0, 0.0},
              spline_nodes: [{0.0, 0.0, -1_000.0}]
          }
      }

      on_exit(fn -> World.remove_position(moving) end)
      World.update_position(moving)

      assert World.nearby_units_exact(:mobs, WorldRef.open(0), {0.0, 0.0, 0.0}, 1.0, 1_500) == [{guid, 0.0}]
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
