defmodule ThistleTea.Game.World.System.OutdoorCaptureTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.OutdoorPvp.CapturePoint
  alias ThistleTea.Game.OutdoorPvp.CapturePoint.Template
  alias ThistleTea.Game.OutdoorPvp.Plaguelands
  alias ThistleTea.Game.OutdoorPvp.Towers
  alias ThistleTea.Game.OutdoorPvp.Towers.Participant
  alias ThistleTea.Game.World.System.OutdoorPvp
  alias ThistleTea.Game.WorldRef

  setup [:server]

  describe "advance/2" do
    test "grants capture credit once and updates regional buffs and ordered meters", %{server: server} do
      %{token: token} = OutdoorPvp.sync(1, WorldRef.open(0), 139, :alliance, server)
      %{token: dungeon_token} = OutdoorPvp.sync(2, WorldRef.instance(329, 1), 2017, :alliance, server)
      %{token: horde_token} = OutdoorPvp.sync(3, WorldRef.instance(289, 1), 2057, :horde, server)
      towers = OutdoorPvp.advance(240_000, server)
      assert CapturePoint.owner(towers.points.northpass) == :alliance
      assert_receive {:outdoor_pvp_credit, ^token, 17_696}
      assert_receive {:outdoor_pvp_update, ^token, states, 11_413}
      assert Enum.take(states, -3) == [{2426, 1}, {2428, 20}, {2427, 60}]
      assert_receive {:outdoor_pvp_update, ^dungeon_token, [], 11_413}
      refute_receive {:outdoor_pvp_update, ^horde_token, _, _}
      OutdoorPvp.advance(241_000, server)
      refute_receive {:outdoor_pvp_credit, _, _}
    end

    test "removes departing members and rejects old subscription identities", %{server: server} do
      %{token: original} = OutdoorPvp.sync(1, WorldRef.open(0), 139, :alliance, server)
      OutdoorPvp.advance(240_000, server)
      assert_receive {:outdoor_pvp_credit, ^original, _}
      assert_receive {:outdoor_pvp_update, ^original, _, _}
      OutdoorPvp.leave(1, server)
      assert OutdoorPvp.advance(241_000, server).members == %{}
      %{token: replacement} = OutdoorPvp.sync(1, WorldRef.open(0), 139, :horde, server)
      assert replacement != original
      towers = OutdoorPvp.advance(242_000, server)
      assert CapturePoint.owner(towers.points.northpass) == nil
      assert_receive {:outdoor_pvp_update, ^replacement, _, nil}
      refute_receive {:outdoor_pvp_credit, _, _}
    end

    test "drops subscriptions when their process exits", %{server: server} do
      task = Task.async(fn -> OutdoorPvp.sync(1, WorldRef.open(0), 139, :alliance, server) end)
      assert is_reference(Task.await(task).token)
      assert OutdoorPvp.advance(240_000, server).members == %{}
      assert OutdoorPvp.tower_snapshot(server).points.northpass.progress == 0
    end
  end

  defp server(_context) do
    template = %Template{
      entry: 181_899,
      radius: 80,
      display_state: 2426,
      position_state: 2427,
      neutral_state: 2428,
      neutral_percent: 20,
      min_time: 480,
      max_time: 1200
    }

    towers = Towers.new(%{181_899 => template})

    server =
      start_supervised!(
        {OutdoorPvp, name: nil, towers: towers, clock: fn -> 0 end, interval_ms: nil, participants: &participants/1}
      )

    %{server: server}
  end

  defp participants(members) do
    {x, y, z, _} = Plaguelands.towers().northpass.position

    for {guid, member} <- members, member.zone == 139 do
      %Participant{guid: guid, team: member.team, world: member.world, position: {x, y, z}, eligible?: true}
    end
  end
end
