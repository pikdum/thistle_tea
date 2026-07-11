defmodule ThistleTea.Game.World.SpawnPool.RuntimeTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.SpawnPool

  @moduletag :dbc_db

  describe "real pool lifecycle" do
    test "runs and recycles exactly one Hogger incarnation" do
      rows = hogger_rows()

      rows
      |> Enum.map(&cell/1)
      |> Enum.uniq()
      |> Enum.each(&Loader.Mob.load/1)

      {first_member, first_pid} = await_running_hogger()
      assert running_hogger_count(rows) == 1

      send(first_pid, {:despawn_creature, 1})

      {_second_member, second_pid} = await_replacement(first_member, first_pid)
      refute first_pid == second_pid
      assert running_hogger_count(rows) == 1

      [{pool_pid, _value}] = Registry.lookup(SpawnPool.Registry, {:pool, 1270})
      DynamicSupervisor.terminate_child(SpawnPool.Supervisor, pool_pid)
    end
  end

  defp hogger_rows do
    Mangos.Repo.all(
      from(c in Mangos.Creature,
        where: c.id == 448,
        select: {c.guid, c.position_x, c.position_y, c.position_z}
      )
    )
  end

  defp cell({_guid, x, y, z}), do: SpatialHash.cell(0, x, y, z)

  defp await_running_hogger(attempts \\ 100)
  defp await_running_hogger(0), do: flunk("Hogger pool did not start")

  defp await_running_hogger(attempts) do
    case SpawnPool.status({:pool, 1270}) do
      %{running: [{:creature, db_guid} = member]} ->
        case EntityRegistry.whereis(Guid.from_low_guid(:mob, 448, db_guid)) do
          pid when is_pid(pid) -> {member, pid}
          nil -> Process.sleep(10) && await_running_hogger(attempts - 1)
        end

      _status ->
        Process.sleep(10) && await_running_hogger(attempts - 1)
    end
  end

  defp await_replacement(old_member, old_pid, attempts \\ 100)
  defp await_replacement(_old_member, _old_pid, 0), do: flunk("Hogger was not recycled")

  defp await_replacement(old_member, old_pid, attempts) do
    case await_running_hogger() do
      {^old_member, ^old_pid} -> Process.sleep(10) && await_replacement(old_member, old_pid, attempts - 1)
      replacement -> replacement
    end
  end

  defp running_hogger_count(rows) do
    Enum.count(rows, fn {db_guid, _x, _y, _z} ->
      is_pid(EntityRegistry.whereis(Guid.from_low_guid(:mob, 448, db_guid)))
    end)
  end
end
