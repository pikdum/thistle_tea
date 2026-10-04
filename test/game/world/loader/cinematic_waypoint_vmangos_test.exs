defmodule ThistleTea.Game.World.Loader.CinematicWaypointVMangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.CinematicWaypoint, as: CinematicWaypointLoader

  @moduletag :vmangos_db

  test "orders each intro's camera path by time" do
    assert :ok = CinematicWaypointLoader.load_all()
    assert [{0, {-8960.0, 517.0, 86.0}} | rest] = CinematicWaypointLoader.get(81)
    timers = Enum.map(rest, &elem(&1, 0))
    assert timers == Enum.sort(timers)
    assert CinematicWaypointLoader.get(999_999) == []
  end
end
