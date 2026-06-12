defmodule ThistleTea.Game.World.ChaseWatchTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.ChaseWatch

  describe "notify_moved/3" do
    test "notifies chasers only after the target crosses their movement threshold" do
      table = table()
      ChaseWatch.init(table)
      ChaseWatch.watch(1, self(), {0.0, 0.0, 0.0}, 1.0, table)

      ChaseWatch.notify_moved(1, {0.5, 0.0, 0.0}, table)
      refute_receive {:target_moved, 1}

      ChaseWatch.notify_moved(1, {1.5, 0.0, 0.0}, table)
      assert_receive {:target_moved, 1}
    end

    test "updates the watched position after notifying" do
      table = table()
      ChaseWatch.init(table)
      ChaseWatch.watch(1, self(), {0.0, 0.0, 0.0}, 1.0, table)

      ChaseWatch.notify_moved(1, {1.5, 0.0, 0.0}, table)
      assert_receive {:target_moved, 1}

      ChaseWatch.notify_moved(1, {1.6, 0.0, 0.0}, table)
      refute_receive {:target_moved, 1}
    end
  end

  describe "unwatch/2" do
    test "removes a chaser from all target watches" do
      table = table()
      ChaseWatch.init(table)
      ChaseWatch.watch(1, self(), {0.0, 0.0, 0.0}, 0.0, table)
      ChaseWatch.watch(2, self(), {0.0, 0.0, 0.0}, 0.0, table)

      ChaseWatch.unwatch(self(), table)
      ChaseWatch.notify_moved(1, {1.0, 0.0, 0.0}, table)
      ChaseWatch.notify_moved(2, {1.0, 0.0, 0.0}, table)

      refute_receive {:target_moved, _target}
    end
  end

  defp table do
    :"chase_watch_test_#{System.unique_integer([:positive])}"
  end
end
