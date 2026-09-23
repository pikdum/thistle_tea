defmodule ThistleTea.Game.World.System.WeatherTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Weather
  alias ThistleTea.Game.Weather.Season
  alias ThistleTea.Game.World.System.Weather, as: WeatherSystem
  alias ThistleTea.Game.WorldRef

  setup [:server]

  describe "sync/4" do
    test "shares zone weather, isolates map copies, and restores reconnects", %{server: server} do
      world = WorldRef.open(0)
      other = WorldRef.instance(0, 1)
      {first, %Weather{}} = WeatherSystem.sync(1, world, 12, server)
      {second, %Weather{}} = WeatherSystem.sync(2, world, 12, server)
      {neighbor, %Weather{}} = WeatherSystem.sync(3, world, 40, server)
      {copy, %Weather{}} = WeatherSystem.sync(4, other, 12, server)
      rain = WeatherSystem.set(world, 12, :rain, 0.8, false, server)
      assert_receive {:weather_changed, ^first, ^rain}
      assert_receive {:weather_changed, ^second, ^rain}
      refute_received {:weather_changed, ^neighbor, _}
      refute_received {:weather_changed, ^copy, _}

      WeatherSystem.leave(1, server)
      {reconnected, ^rain} = WeatherSystem.sync(1, world, 12, server)
      refute first == reconnected
      assert {_new, %Weather{type: :fine}} = WeatherSystem.sync(1, world, 40, server)
      WeatherSystem.set(world, 12, :rain, 0.9, false, server)
      refute_received {:weather_changed, ^reconnected, _}
    end

    test "cleans up dead owners and does not let a different owner unsubscribe them", %{server: server} do
      parent = self()

      owner =
        spawn(fn ->
          WeatherSystem.sync(1, WorldRef.open(0), 12, server)
          send(parent, :subscribed)

          receive do
            :stop -> :ok
          end
        end)

      assert_receive :subscribed
      WeatherSystem.leave(1, server)
      assert WeatherSystem.snapshot(server).members[1].pid == owner
      send(owner, :stop)
      await_removed(server, 1)
      assert WeatherSystem.snapshot(server).members == %{}
    end
  end

  describe "weather rolls" do
    test "uses the season at roll time, ignores stale timers, and prunes empty zones", %{server: server} do
      key = {WorldRef.open(0), 12}
      {token, _weather} = WeatherSystem.sync(1, elem(key, 0), 12, server)
      before = WeatherSystem.snapshot(server).zones[key]
      assert Process.read_timer(before.timer) > 0
      send(server, {:roll, key, before.token})
      assert_receive {:weather_changed, ^token, %Weather{type: :rain, grade: 0.3333}}
      current = WeatherSystem.snapshot(server).zones[key]
      send(server, {:roll, key, before.token})
      assert WeatherSystem.snapshot(server).zones[key] == current
      WeatherSystem.leave(1, server)
      send(server, {:roll, key, current.token})
      assert WeatherSystem.snapshot(server).zones == %{}
    end

    test "permanent controls survive rolls until resumed and teardown removes their timers", %{server: server} do
      world = WorldRef.instance(529, 2)
      {token, _weather} = WeatherSystem.sync(1, world, 12, server)
      snow = WeatherSystem.set(world, 12, :snow, 0.8, true, server)
      assert_receive {:weather_changed, ^token, ^snow}
      assert WeatherSystem.advance(world, 12, server) == snow
      refute_received {:weather_changed, ^token, _}
      WeatherSystem.resume(world, 12, server)
      assert WeatherSystem.advance(world, 12, server).grade == 0.9999
      timer = WeatherSystem.snapshot(server).zones[{world, 12}].timer
      WeatherSystem.clear_world(world, server)
      assert WeatherSystem.snapshot(server) == %{zones: %{}, members: %{}}
      assert Process.read_timer(timer) == false
    end
  end

  defp server(_context) do
    lookup = fn
      12, :fall -> %Season{rain: 100}
      _zone, _season -> nil
    end

    sample = fn -> %{change: 60, kind: 1, radical: 0, intensity: 0, grade: 1.0} end

    server =
      start_supervised!({WeatherSystem, name: nil, lookup: lookup, date: fn -> ~D[2026-09-23] end, sample: sample})

    %{server: server}
  end

  defp await_removed(server, guid, attempts \\ 30)
  defp await_removed(_server, _guid, 0), do: flunk("weather subscription survived owner exit")

  defp await_removed(server, guid, attempts) do
    if Map.has_key?(WeatherSystem.snapshot(server).members, guid) do
      Process.sleep(5)
      await_removed(server, guid, attempts - 1)
    end
  end
end
