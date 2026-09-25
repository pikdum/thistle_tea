defmodule ThistleTea.Game.World.BattlegroundBuffsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Battleground.Buffs
  alias ThistleTea.Game.WorldRef

  describe "start_link/1" do
    test "rotates consumed pickups after the delay and cleans up when the match ends" do
      owner = spawn(fn -> receive do: (:stop -> :ok) end)
      parent = self()
      position = {1.0, 2.0, 3.0, 4.0}
      world = WorldRef.instance(529, System.unique_integer([:positive]))

      spawn_pickup = fn world, entry, position ->
        pid = spawn(fn -> receive do: (:consume -> :ok) end)
        send(parent, {:pickup, pid, world, entry, position})
        {:ok, pid}
      end

      choose = fn entries ->
        index = Process.get(:next_buff, 0)
        Process.put(:next_buff, index + 1)
        Enum.at(entries, rem(index, length(entries)))
      end

      {:ok, manager} =
        Buffs.start_link(
          world: world,
          owner: owner,
          positions: [position],
          spawn: spawn_pickup,
          choose: choose,
          stop: &Process.exit(&1, :shutdown),
          respawn_ms: 100
        )

      manager_monitor = Process.monitor(manager)
      on_exit(fn -> Process.exit(owner, :shutdown) end)
      assert_receive {:pickup, first, ^world, 179_871, ^position}
      send(first, :consume)
      refute_receive {:pickup, _, _, _, _}, 30
      assert_receive {:pickup, second, ^world, 179_904, ^position}, 1_000
      second_monitor = Process.monitor(second)
      assert :sys.get_state(manager).running == %{0 => second}
      send(owner, :stop)
      assert_receive {:DOWN, ^manager_monitor, :process, ^manager, :normal}
      assert_receive {:DOWN, ^second_monitor, :process, ^second, :shutdown}
      refute_receive {:pickup, _, _, _, _}, 120
    end
  end
end
