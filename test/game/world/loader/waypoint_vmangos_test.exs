defmodule ThistleTea.Game.World.Loader.WaypointVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Waypoints
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.Waypoint, as: WaypointLoader

  @moduletag :vmangos_db

  setup do
    WaypointLoader.init()
    WaypointLoader.load_all()
    :ok
  end

  test "loads special escort paths with their movement scripts" do
    mob = %Mob{object: %Object{guid: Guid.from_low_guid(:mob, 7_784, 1)}}

    step = %ScriptStep{
      command: :start_waypoints,
      datalong: 3,
      datalong4: 1,
      dataint2: 7_784
    }

    assert %WaypointRoute{first_point: 1, destination_point: 1, repeat?: true, points: points} =
             Waypoints.resolve(WaypointLoader.context(), mob, step)

    assert map_size(points) == 54
    assert Enum.count(points, fn {_point, waypoint} -> waypoint.script_steps != [] end) == 3
  end

  test "resolves guid and template path origins" do
    context = WaypointLoader.context()

    guid_mob = %Mob{object: %Object{guid: Guid.from_low_guid(:mob, 1, 11_006)}}
    guid_step = %ScriptStep{command: :start_waypoints, datalong: 1}
    assert %WaypointRoute{points: guid_points} = Waypoints.resolve(context, guid_mob, guid_step)
    assert map_size(guid_points) == 9

    entry_mob = %Mob{object: %Object{guid: Guid.from_low_guid(:mob, 1_446, 1)}}
    entry_step = %ScriptStep{command: :start_waypoints, datalong: 2}
    assert %WaypointRoute{points: entry_points} = Waypoints.resolve(context, entry_mob, entry_step)
    assert map_size(entry_points) == 27
  end
end
