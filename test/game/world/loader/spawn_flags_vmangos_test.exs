defmodule ThistleTea.Game.World.Loader.SpawnFlagsVmangosTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.SpatialGrid
  alias ThistleTea.Game.Core.WorldRef

  @moduletag :vmangos_db

  @lord_valthalak 301_240
  @henze_faulk 81_163
  @disabled_game_object 9496

  describe "Mangos.Creature.query_bounds/3" do
    test "holds back disabled spawns and keeps spawns that are dead by default" do
      refute @lord_valthalak in creature_guids(229, 52.6614, -535.253)

      assert [henze] =
               0
               |> creature_rows(-9129.59, -984.313)
               |> Enum.filter(&(&1.guid == @henze_faulk))

      assert Mangos.Creature.dead?(henze)
      refute Mangos.Creature.held_back?(henze)
    end
  end

  describe "Mangos.GameObject.query_bounds/3" do
    test "holds back disabled spawns" do
      bounds = bounds(1, -7144.21, 1402.09)
      guids = 1 |> Mangos.GameObject.query_bounds(bounds) |> Mangos.Repo.all() |> Enum.map(& &1.guid)
      refute @disabled_game_object in guids

      assert [%Mangos.GameObject{spawn_flags: 2}] =
               [@disabled_game_object] |> Mangos.GameObject.query_guids() |> Mangos.Repo.all()
    end
  end

  defp creature_guids(map, x, y), do: map |> creature_rows(x, y) |> Enum.map(& &1.guid)

  defp creature_rows(map, x, y), do: map |> Mangos.Creature.query_bounds(bounds(map, x, y)) |> Mangos.Repo.all()

  defp bounds(map, x, y), do: map |> WorldRef.open() |> SpatialGrid.cell(x, y, 0.0) |> SpatialGrid.cell_bounds()
end
