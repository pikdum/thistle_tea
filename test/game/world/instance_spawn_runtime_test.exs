defmodule ThistleTea.Game.World.InstanceSpawnRuntimeTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.WorldRef

  @moduletag :vmangos_db

  describe "instance cell activation" do
    test "materializes disjoint RFC spawns in copies of the same cell" do
      first_world = WorldRef.instance(389, System.unique_integer([:positive]))
      second_world = WorldRef.instance(389, System.unique_integer([:positive]))
      position = {-45.0298, -27.7645, -21.2917}
      first_cell = SpatialHash.cell(first_world, elem(position, 0), elem(position, 1), elem(position, 2))
      second_cell = put_elem(first_cell, 0, second_world)

      on_exit(fn ->
        SpawnPool.stop_world(first_world)
        SpawnPool.stop_world(second_world)
        World.stop_world_entities(first_world)
        World.stop_world_entities(second_world)
      end)

      Loader.Mob.load(first_cell)
      Loader.Mob.load(second_cell)

      {first_guids, second_guids} = await_spawns(first_world, second_world, position)

      assert MapSet.disjoint?(first_guids, second_guids)
      assert MapSet.size(first_guids) == MapSet.size(second_guids)
    end
  end

  defp await_spawns(first_world, second_world, position, attempts \\ 100)

  defp await_spawns(_first_world, _second_world, _position, 0) do
    flunk("RFC instance spawns did not start")
  end

  defp await_spawns(first_world, second_world, position, attempts) do
    first_guids = spawned_guids(first_world, position)
    second_guids = spawned_guids(second_world, position)

    if MapSet.size(first_guids) > 0 and MapSet.size(first_guids) == MapSet.size(second_guids) do
      {first_guids, second_guids}
    else
      Process.sleep(10)
      await_spawns(first_world, second_world, position, attempts - 1)
    end
  end

  defp spawned_guids(world, position) do
    world
    |> World.nearby_mobs_at(position, 180.0)
    |> MapSet.new(&elem(&1, 0))
  end
end
