defmodule ThistleTea.Game.World.System.CellActivatorTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.System.CellActivator
  alias ThistleTea.Game.WorldRef

  describe "activate/2" do
    test "loads newly activated cells once" do
      parent = self()
      loader = fn cell -> send(parent, {:loaded, cell}) end
      name = :"cell_activator_test_#{System.unique_integer([:positive])}"

      start_supervised!({CellActivator, name: name, loader: loader})

      CellActivator.activate([{0, 1, 2}, {0, 1, 3}], name)
      assert_receive {:loaded, {0, 1, 2}}
      assert_receive {:loaded, {0, 1, 3}}

      CellActivator.activate([{0, 1, 2}], name)
      refute_receive {:loaded, {0, 1, 2}}, 50
    end

    test "invalidate allows cells to load again" do
      parent = self()
      loader = fn cell -> send(parent, {:loaded, cell}) end
      name = :"cell_activator_test_#{System.unique_integer([:positive])}"

      start_supervised!({CellActivator, name: name, loader: loader})

      CellActivator.activate([{0, 1, 2}], name)
      assert_receive {:loaded, {0, 1, 2}}

      CellActivator.invalidate(name)
      CellActivator.activate([{0, 1, 2}], name)
      assert_receive {:loaded, {0, 1, 2}}
    end

    test "bounds concurrent cell loads" do
      parent = self()

      loader = fn cell ->
        send(parent, {:started, cell, self()})
        receive do: (:continue -> :ok)
      end

      name = :"cell_activator_test_#{System.unique_integer([:positive])}"
      start_supervised!({CellActivator, name: name, loader: loader, max_concurrency: 2})

      CellActivator.activate([{0, 1, 1}, {0, 1, 2}, {0, 1, 3}], name)

      assert_receive {:started, _cell, first}
      assert_receive {:started, _cell, second}
      refute_receive {:started, _cell, _pid}, 50

      send(first, :continue)
      send(second, :continue)
      assert_receive {:started, _cell, third}
      send(third, :continue)
    end

    test "retries a failed cell load" do
      parent = self()
      attempts = start_supervised!({Agent, fn -> 0 end})

      loader = fn cell ->
        attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})

        if attempt == 1 do
          exit(:load_failed)
        else
          send(parent, {:loaded, cell})
        end
      end

      name = :"cell_activator_test_#{System.unique_integer([:positive])}"

      start_supervised!({CellActivator, name: name, loader: loader, max_concurrency: 1, retry_delay_ms: 10})

      CellActivator.activate([{0, 1, 2}], name)
      assert_receive {:loaded, {0, 1, 2}}
      assert Agent.get(attempts, & &1) == 2

      CellActivator.activate([{0, 1, 2}], name)
      refute_receive {:loaded, {0, 1, 2}}, 50
    end
  end

  describe "sweep" do
    test "re-asserts wanted cells and deactivates them after players leave" do
      world = System.unique_integer([:positive])
      occupied = start_supervised!({Agent, fn -> [{world, 10, 10}] end})
      pid = start_sweeper(occupied, grace_ms: 0)

      send(pid, :sweep)
      assert_receive {:loaded, {^world, 10, 10}}

      Agent.update(occupied, fn _cells -> [] end)
      send(pid, :sweep)
      assert_receive {:deactivated, cells}
      assert MapSet.member?(cells, {world, 10, 10})

      CellActivator.activate([{world, 10, 10}], pid)
      assert_receive {:loaded, {^world, 10, 10}}
    end

    test "keeps cells wanted by players loaded" do
      world = System.unique_integer([:positive])
      occupied = start_supervised!({Agent, fn -> [{world, 10, 10}] end})
      pid = start_sweeper(occupied, grace_ms: 0)

      send(pid, :sweep)
      assert_receive {:loaded, {^world, 10, 10}}

      send(pid, :sweep)
      send(pid, :sweep)
      refute_receive {:deactivated, _cells}, 50
    end

    test "invalidate keeps running cells eligible for deactivation" do
      world = System.unique_integer([:positive])
      occupied = start_supervised!({Agent, fn -> [] end})
      pid = start_sweeper(occupied, grace_ms: 0)

      CellActivator.activate([{world, 1, 1}], pid)
      assert_receive {:loaded, {^world, 1, 1}}

      CellActivator.invalidate(pid)
      send(pid, :sweep)
      assert_receive {:deactivated, cells}
      assert MapSet.member?(cells, {world, 1, 1})
    end

    test "tears down an open world after it stays empty" do
      world = System.unique_integer([:positive])
      occupied = start_supervised!({Agent, fn -> [{world, 1, 1}] end})
      pid = start_sweeper(occupied, grace_ms: 999_999_999, world_empty_timeout_ms: 0)

      send(pid, :sweep)
      assert_receive {:loaded, {^world, 1, 1}}

      Agent.update(occupied, fn _cells -> [] end)
      send(pid, :sweep)
      assert_receive {:torn_down, ^world}

      CellActivator.activate([{world, 1, 1}], pid)
      assert_receive {:loaded, {^world, 1, 1}}
    end

    test "tears down a world kept alive only by resident pools" do
      world = System.unique_integer([:positive])
      occupied = start_supervised!({Agent, fn -> [] end})

      pid =
        start_sweeper(occupied,
          grace_ms: 0,
          world_empty_timeout_ms: 0,
          pool_worlds: fn -> [world] end
        )

      send(pid, :sweep)
      assert_receive {:torn_down, ^world}
    end

    test "does not tear down worlds with players present" do
      world = System.unique_integer([:positive])
      occupied = start_supervised!({Agent, fn -> [{world, 1, 1}] end})
      pid = start_sweeper(occupied, grace_ms: 999_999_999, world_empty_timeout_ms: 0)

      send(pid, :sweep)
      assert_receive {:loaded, {^world, 1, 1}}

      send(pid, :sweep)
      send(pid, :sweep)
      refute_receive {:torn_down, _world}, 50
    end

    test "leaves instanced worlds alone" do
      world = WorldRef.instance(389, System.unique_integer([:positive]))
      occupied = start_supervised!({Agent, fn -> [] end})
      pid = start_sweeper(occupied, grace_ms: 0, world_empty_timeout_ms: 0)

      CellActivator.activate([{world, 1, 1}], pid)
      assert_receive {:loaded, {^world, 1, 1}}

      send(pid, :sweep)
      refute_receive {:deactivated, _cells}, 50
      refute_receive {:torn_down, _world}, 50
    end
  end

  defp start_sweeper(occupied, opts) do
    parent = self()

    defaults = [
      name: :"cell_activator_test_#{System.unique_integer([:positive])}",
      loader: fn cell -> send(parent, {:loaded, cell}) end,
      player_cells: fn -> Agent.get(occupied, & &1) end,
      pool_worlds: fn -> [] end,
      deactivator: fn cells, _wanted ->
        send(parent, {:deactivated, cells})
        cells
      end,
      world_teardown: fn world -> send(parent, {:torn_down, world}) end
    ]

    start_supervised!({CellActivator, Keyword.merge(defaults, opts)})
  end
end
