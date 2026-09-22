defmodule ThistleTea.Game.World.CombatLeashesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.CombatLeash.Owner
  alias ThistleTea.Game.Entity.Data.CombatLeash.Ref
  alias ThistleTea.Game.World.CombatLeashes
  alias ThistleTea.Game.WorldRef

  setup [:leashes]

  describe "event/4" do
    test "retains an idle owner's clock for its later fight and releases idle ownership", %{server: server, a: a, b: b} do
      owner = %Owner{world: a.world, guid: a.guid, incarnation: a.incarnation, pid: self()}
      CombatLeashes.event(b, {:start, 1_000, owner}, self(), server)
      CombatLeashes.event(b, {:extend, 2_000}, self(), server)
      CombatLeashes.event(a, {:start, 3_000, nil}, self(), server)
      assert CombatLeashes.last_extended_at(b, server) == 3_000
      CombatLeashes.event(a, :stop, self(), server)
      CombatLeashes.event(a, {:start, 4_000, nil}, self(), server)
      assert CombatLeashes.last_extended_at(b, server) == 3_000
      CombatLeashes.event(a, :stop, self(), server)
      CombatLeashes.event(b, :stop, self(), server)
      CombatLeashes.event(b, {:start, 5_000, owner}, self(), server)
      CombatLeashes.event(b, :stop, self(), server)
      assert map_size(:sys.get_state(server).clocks) == 1
      CombatLeashes.event(%{a | generation: 9}, :stop, self(), server)
      assert :sys.get_state(server).clocks == %{}
      assert :sys.get_state(server).monitors == %{}
    end

    test "does not adopt stale creature ownership or link across world copies", %{server: server, a: a, b: b} do
      CombatLeashes.event(a, {:start, 1_000, nil}, self(), server)
      owner = %Owner{world: a.world, guid: a.guid, incarnation: a.incarnation, pid: self()}

      for invalid <- [
            %{owner | incarnation: 0},
            %{owner | pid: server},
            %{owner | world: WorldRef.instance(0, 99)}
          ] do
        CombatLeashes.event(b, {:start, 2_000, invalid}, self(), server)
        CombatLeashes.event(b, {:extend, 3_000}, self(), server)
        assert CombatLeashes.last_extended_at(a, server) == 1_000
        CombatLeashes.event(b, :stop, self(), server)
      end
    end

    test "shares extensions in both directions and retains the clock after its source leaves", %{
      server: server,
      a: a,
      b: b
    } do
      :ok = CombatLeashes.event(a, {:start, -20_000, nil}, self(), server)
      :ok = CombatLeashes.event(b, {:start, -18_500, a}, self(), server)
      assert CombatLeashes.last_extended_at(b, server) == -20_000
      CombatLeashes.event(b, {:extend, -15_000}, self(), server)
      assert CombatLeashes.last_extended_at(a, server) == -15_000
      CombatLeashes.event(a, {:extend, -16_000}, self(), server)
      assert CombatLeashes.last_extended_at(b, server) == -15_000
      CombatLeashes.event(a, :stop, self(), server)
      assert CombatLeashes.last_extended_at(a, server) == nil
      assert CombatLeashes.last_extended_at(b, server) == -15_000
      CombatLeashes.event(b, {:extend, -10_000}, self(), server)
      assert CombatLeashes.last_extended_at(b, server) == -10_000
      CombatLeashes.event(b, :stop, self(), server)
      assert :sys.get_state(server).clocks == %{}
    end

    test "rejects stale extensions and assistance from a previous fight or incarnation", %{server: server, a: a, b: b} do
      CombatLeashes.event(a, {:start, 0, nil}, self(), server)
      CombatLeashes.event(a, :stop, self(), server)
      next = %{a | generation: 2}
      CombatLeashes.event(next, {:start, 20_000, nil}, self(), server)
      assert :stale = CombatLeashes.event(a, {:start, 30_000, nil}, self(), server)
      assert :stale = CombatLeashes.event(a, {:extend, 30_000}, self(), server)
      assert :stale = CombatLeashes.event(a, :stop, self(), server)
      assert :stale = CombatLeashes.event(next, :stop, server, server)
      CombatLeashes.event(b, {:start, 21_000, a}, self(), server)
      assert CombatLeashes.last_extended_at(b, server) == 21_000
      CombatLeashes.event(next, {:extend, 22_000}, self(), server)
      assert CombatLeashes.last_extended_at(b, server) == 21_000
      replacement = %{next | incarnation: 3, generation: 1}
      CombatLeashes.event(replacement, {:start, 23_000, nil}, self(), server)
      assert :stale = CombatLeashes.event(next, {:start, 30_000, nil}, self(), server)
      assert CombatLeashes.last_extended_at(next, server) == nil
      assert :stale = CombatLeashes.event(next, {:extend, 30_000}, self(), server)
    end

    test "isolates world copies and releases only the stopped world", %{server: server, a: a, b: b} do
      other = %{b | world: WorldRef.instance(0, 2)}
      CombatLeashes.event(a, {:start, 0, nil}, self(), server)
      CombatLeashes.event(other, {:start, 1_000, a}, self(), server)
      CombatLeashes.event(a, {:extend, 2_000}, self(), server)
      assert CombatLeashes.last_extended_at(other, server) == 1_000
      CombatLeashes.stop_world(a.world, server)
      assert CombatLeashes.last_extended_at(a, server) == nil
      assert CombatLeashes.last_extended_at(other, server) == 1_000
    end
  end

  describe "handle_info/2" do
    test "removes a terminated owner without discarding its helpers' clock", %{server: server, a: a, b: b} do
      owner =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      monitor = Process.monitor(owner)
      CombatLeashes.event(a, {:start, 0, nil}, owner, server)
      CombatLeashes.event(b, {:start, 1_000, a}, self(), server)
      send(owner, :stop)
      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
      await_detached(server, a, 100)
      assert CombatLeashes.last_extended_at(b, server) == 0
      assert map_size(:sys.get_state(server).clocks) == 1
    end
  end

  defp leashes(_context) do
    server = start_supervised!({CombatLeashes, name: nil})
    a = %Ref{world: WorldRef.open(0), guid: 1, incarnation: 1, generation: 1}
    %{server: server, a: a, b: %{a | guid: 2, incarnation: 2}}
  end

  defp await_detached(_server, _ref, 0), do: flunk("terminated owner remained registered")

  defp await_detached(server, ref, attempts) do
    if CombatLeashes.last_extended_at(ref, server) do
      Process.sleep(5)
      await_detached(server, ref, attempts - 1)
    end
  end
end
