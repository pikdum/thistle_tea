defmodule ThistleTea.Game.World.SpawnPool.GameObjectRuntimeTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.World.SpawnPool.Catalog

  @moduletag :vmangos_db

  describe "real game-object pool lifecycle" do
    test "keeps a resource pool at its configured limit while recycling" do
      rows = resource_rows()

      rows
      |> Map.values()
      |> Enum.map(&cell/1)
      |> Enum.uniq()
      |> Enum.each(&SpawnPool.activate({:pool, 4303}, &1))

      running = await_running(37)
      {first_member, first_pid} = first_incarnation(running, rows)

      send(first_pid, :chest_respawn)

      running = await_replacement(first_member, first_pid, rows)
      assert length(running) == 37

      [{pool_pid, _value}] = Registry.lookup(SpawnPool.Registry, {:pool, 4303})
      DynamicSupervisor.terminate_child(SpawnPool.Supervisor, pool_pid)
    end
  end

  defp resource_rows do
    guids = for %{kind: :game_object, id: guid} <- Catalog.root_members(4303), do: guid

    from(g in Mangos.GameObject,
      where: g.guid in ^guids,
      select: {g.guid, g.id, g.map, g.position_x, g.position_y, g.position_z}
    )
    |> Mangos.Repo.all()
    |> Map.new(fn {guid, entry, map, x, y, z} -> {guid, {entry, map, x, y, z}} end)
  end

  defp cell({_entry, map, x, y, z}), do: SpatialHash.cell(map, x, y, z)

  defp await_running(expected, attempts \\ 200)
  defp await_running(_expected, 0), do: flunk("resource pool did not reach its configured limit")

  defp await_running(expected, attempts) do
    case SpawnPool.status({:pool, 4303}).running do
      running when length(running) == expected -> running
      _running -> Process.sleep(10) && await_running(expected, attempts - 1)
    end
  end

  defp first_incarnation([{:game_object, db_guid} = member | _rest], rows) do
    {entry, _map, _x, _y, _z} = Map.fetch!(rows, db_guid)
    {member, EntityRegistry.whereis(Guid.from_low_guid(:game_object, entry, db_guid))}
  end

  defp await_replacement(old_member, old_pid, rows, attempts \\ 200)
  defp await_replacement(_old_member, _old_pid, _rows, 0), do: flunk("resource node was not recycled")

  defp await_replacement(old_member, old_pid, rows, attempts) do
    running = await_running(37)

    if incarnation_replaced?(running, old_member, old_pid, rows) do
      running
    else
      Process.sleep(10)
      await_replacement(old_member, old_pid, rows, attempts - 1)
    end
  end

  defp incarnation_replaced?(running, old_member, old_pid, rows) do
    case Enum.find(running, &(&1 == old_member)) do
      {:game_object, db_guid} ->
        {entry, _map, _x, _y, _z} = Map.fetch!(rows, db_guid)
        EntityRegistry.whereis(Guid.from_low_guid(:game_object, entry, db_guid)) != old_pid

      nil ->
        true
    end
  end
end
