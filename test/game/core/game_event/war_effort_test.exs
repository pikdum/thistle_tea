defmodule ThistleTea.Game.Core.GameEvent.WarEffortTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GameEvent.Rule
  alias ThistleTea.Game.Core.GameEvent.WarEffort

  describe "active_events/2" do
    test "holds the war complete so only the post-war watch runs" do
      assert Rule.for_event(85) == WarEffort
      assert WarEffort.active_events(~U[2026-10-03 12:00:00Z], MapSet.new()) == [86]
      assert WarEffort.boundaries(~U[2026-10-03 12:00:00Z]) == []
    end
  end
end
