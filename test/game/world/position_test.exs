defmodule ThistleTea.Game.World.PositionTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Movement
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.Position.ClientMotion
  alias ThistleTea.Game.World.Position.Spline
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Test.Unique

  describe "snapshot/2" do
    test "retains legacy spline records" do
      guid = Guid.from_low_guid(:mob, 1, unique_guid())
      entity = mob(guid)
      world = WorldRef.open(0)
      on_exit(fn -> World.remove_position(entity) end)
      World.update_position(entity)
      :ets.insert(:entity_movement, {guid, {world, {0.0, 0.0, 0.0}, [{10.0, 0.0, 0.0}], 1_000, 1_000}})

      assert Position.snapshot(guid, 1_500) == {{world, 5.0, 0.0, 0.0}, true}
      assert Position.snapshot(guid, 2_001) == {{world, 10.0, 0.0, 0.0}, false}
    end

    test "captures spline motion through arrival and removal" do
      guid = Guid.from_low_guid(:mob, 1, unique_guid())
      moving = mob(guid)
      world = WorldRef.open(0)
      on_exit(fn -> World.remove_position(moving) end)
      World.update_position(moving)

      assert Position.snapshot(guid, 1_500) == {{world, 5.0, 0.0, 0.0}, true}
      assert Position.snapshot(guid, 2_000) == {{world, 10.0, 0.0, 0.0}, true}
      assert Position.snapshot(guid, 2_001) == {{world, 10.0, 0.0, 0.0}, false}

      World.update_position(stop_at(moving, {10.0, 0.0, 0.0, 0.0}))
      assert Position.snapshot(guid, 2_001) == {{world, 10.0, 0.0, 0.0}, false}
      World.remove_position(moving)
      assert Position.snapshot(guid, 2_001) == {nil, false}
    end

    test "captures bounded client motion at its expiry" do
      guid = Guid.from_low_guid(:player, unique_guid())
      character = struct(Character, Map.from_struct(stop_at(mob(guid), {0.0, 0.0, 0.0, 0.0})))
      projection = Position.client_motion(character, {10.0, 0.0, 0.0}, 1_000, 500)
      on_exit(fn -> World.remove_position(character) end)
      Position.put(character, :players, projection)

      assert Position.snapshot(guid, 1_250) == {{WorldRef.open(0), 2.5, 0.0, 0.0}, true}
      assert Position.snapshot(guid, 1_500) == {{WorldRef.open(0), 5.0, 0.0, 0.0}, true}
      assert Position.snapshot(guid, 1_501) == {{WorldRef.open(0), 5.0, 0.0, 0.0}, false}
    end
  end

  describe "World.position_snapshot/3" do
    @tag :namigator_maps
    test "grounds an airborne observation without changing its projected height" do
      guid = Guid.from_low_guid(:mob, 1, unique_guid())
      world = WorldRef.open(451)
      SpatialHash.insert(:mobs, guid, world, 16_303.2, 16_318.1, 100.0)
      on_exit(fn -> SpatialHash.remove(:mobs, guid) end)

      assert {{^world, x, y, 100.0}, {^world, x, y, grounded_z}, false} =
               World.position_snapshot(guid, %{airborne?: true}, 1_000)

      assert grounded_z < 100.0

      assert World.position_snapshot(guid, %{airborne?: false}, 1_000) ==
               {{world, x, y, 100.0}, {world, x, y, 100.0}, false}
    end

    test "uses recent movement from the supplied observation" do
      guid = Guid.from_low_guid(:mob, 1, unique_guid())
      entity = stop_at(mob(guid), {5.0, 0.0, 0.0, 0.0})
      World.update_position(entity)
      Metadata.put(guid, %{moving_until: 9_000})

      on_exit(fn ->
        World.remove_position(entity)
        Metadata.delete(guid)
      end)

      position = {WorldRef.open(0), 5.0, 0.0, 0.0}
      assert World.position_snapshot(guid, %{moving_until: 1_500}, 1_499) == {position, position, true}
      assert World.position_snapshot(guid, %{moving_until: 1_500}, 1_500) == {position, position, false}
      assert World.position_snapshot(guid, nil, 1_000) == {position, position, false}
    end
  end

  describe "put/2" do
    test "projects a falling corpse with the owner's acceleration and stops at the floor" do
      guid = Guid.from_low_guid(:mob, 1, unique_guid())
      corpse = mob(guid) |> stop_at({0.0, 0.0, 30.0, 0.0}) |> Movement.fall_to(10.0, 1_000)
      on_exit(fn -> World.remove_position(corpse) end)
      World.update_position(corpse)
      assert %Spline{falling?: true} = Position.projection(guid)
      assert {_, +0.0, +0.0, z} = World.position(guid, 1_500)
      assert_in_delta z, elem(Movement.sync_position(corpse, 1_500).movement_block.position, 2), 0.00001
      assert Position.snapshot(guid, 1_500) == {{WorldRef.open(0), 0.0, 0.0, z}, true}
      assert {_, +0.0, +0.0, 10.0} = World.position(guid, 10_000)
      landed = Movement.sync_position(corpse, 10_000)
      World.update_position(landed)
      assert Position.projection(guid) == nil
    end

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

  defp unique_guid, do: Unique.integer()
end
