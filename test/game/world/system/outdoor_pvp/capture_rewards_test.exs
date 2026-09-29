defmodule ThistleTea.Game.World.System.OutdoorPvp.CaptureRewardsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.OutdoorPvp.CapturePoint
  alias ThistleTea.Game.Core.OutdoorPvp.CapturePoint.Template
  alias ThistleTea.Game.Core.OutdoorPvp.Towers
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Graveyards
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader
  alias ThistleTea.Game.World.System.OutdoorPvp.CaptureRewards

  describe "reconcile/2" do
    setup [:templates]

    test "retains live services and removes every old owner resource on loss" do
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

      neutral = Towers.new(%{181_899 => template})
      captured = %{neutral | points: %{northpass: CapturePoint.advance(neutral.points.northpass, 1, 0, 240_000)}}
      resources = CaptureRewards.reconcile(%{}, captured)
      on_exit(fn -> CaptureRewards.stop(resources) end)
      assert map_size(resources) == 2
      assert CaptureRewards.reconcile(resources, captured) == resources

      for {_key, {_spec, guid}} <- resources do
        assert is_pid(Entity.pid(guid))
        assert {world, _, _, _} = World.position(guid)
        assert world == WorldRef.open(0)
      end

      assert CaptureRewards.reconcile(resources, neutral) == %{}

      for {_key, {_spec, guid}} <- resources do
        assert Entity.pid(guid) == nil
        assert World.position(guid) == nil
      end
    end
  end

  defp templates(_context) do
    entries = [181_682, 180_100]
    original = Enum.flat_map(entries, &:ets.lookup(TemplateLoader, &1))
    controls = :ets.lookup(Graveyards, 927)

    for entry <- entries,
        do: TemplateLoader.put(%GameObjectTemplate{entry: entry, type: 5, size: 1.0, flags: 0, data: []})

    on_exit(fn ->
      Enum.each(entries, &:ets.delete(TemplateLoader, &1))
      :ets.insert(TemplateLoader, original)
      :ets.delete(Graveyards, 927)
      :ets.insert(Graveyards, controls)
    end)

    :ok
  end
end
