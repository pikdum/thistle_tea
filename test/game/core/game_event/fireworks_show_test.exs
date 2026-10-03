defmodule ThistleTea.Game.Core.GameEvent.FireworksShowTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GameEvent.FireworksShow

  @fireworks 6
  @toasting_goblets 39
  @new_year 34
  @july_4th 41

  describe "active_events/2" do
    test "shows fireworks for the first ten minutes of each night hour, then toasts at New Year's" do
      new_year = MapSet.new([@new_year])

      assert FireworksShow.active_events(~U[2026-12-31 18:05:00Z], new_year) == [@fireworks]
      assert FireworksShow.active_events(~U[2026-12-31 18:10:00Z], new_year) == [@toasting_goblets]
      assert FireworksShow.active_events(~U[2026-12-31 18:20:59Z], new_year) == [@toasting_goblets]
      assert FireworksShow.active_events(~U[2026-12-31 18:21:00Z], new_year) == []
      assert FireworksShow.active_events(~U[2027-01-01 06:09:59Z], new_year) == [@fireworks]
      assert FireworksShow.active_events(~U[2027-01-01 07:05:00Z], new_year) == []
    end

    test "skips the toast on the summer holidays and stays dark without one" do
      assert FireworksShow.active_events(~U[2026-07-04 23:05:00Z], MapSet.new([@july_4th])) == [@fireworks]
      assert FireworksShow.active_events(~U[2026-07-04 23:15:00Z], MapSet.new([@july_4th])) == []
      assert FireworksShow.active_events(~U[2026-07-05 23:05:00Z], MapSet.new()) == []
    end
  end

  describe "boundaries/1" do
    test "lists the coming quarter-hour changes in order" do
      assert Enum.take(FireworksShow.boundaries(~U[2026-12-31 18:05:00Z]), 3) ==
               [~U[2026-12-31 18:10:00Z], ~U[2026-12-31 18:21:00Z], ~U[2026-12-31 19:00:00Z]]
    end
  end
end
