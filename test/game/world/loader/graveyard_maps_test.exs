defmodule ThistleTea.Game.World.Loader.GraveyardMapsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Dungeon
  alias ThistleTea.Game.World.Loader.Graveyard
  alias ThistleTea.Game.World.Loader.MapTemplate

  @moduletag :namigator_maps

  setup [:cache_ragefire_graveyards]

  describe "closest/3" do
    test "releases an unlabelled dungeon entrance to its linked zone graveyard" do
      position = {0.7976431250572205, -8.353290557861328, -15.566657066345215}
      assert %{id: 850} = Graveyard.closest(389, position, 67)
      assert %{id: 32} = Graveyard.closest(389, position, 469)
      assert Graveyard.closest(999, {0.0, 0.0, 0.0}, 67) == nil
    end
  end

  defp cache_ragefire_graveyards(_context) do
    previous_dungeons = :ets.lookup(MapTemplate, :dungeons)
    previous_graveyards = :ets.lookup(Graveyard, 2437)

    dungeon = %Dungeon{map_id: 389, zone_id: 2437, ghost_entrance: {1, 1816.76, -4423.37}}
    :ets.insert(MapTemplate, {:dungeons, %{389 => dungeon}})

    :ets.insert(Graveyard, {
      2437,
      [
        %{id: 32, map: 1, position: {233.458, -4793.73, 10.188}, faction: 0},
        %{id: 850, map: 1, position: {1177.78, -4464.24, 21.354}, faction: 67}
      ]
    })

    on_exit(fn ->
      :ets.delete(MapTemplate, :dungeons)
      :ets.insert(MapTemplate, previous_dungeons)
      :ets.delete(Graveyard, 2437)
      :ets.insert(Graveyard, previous_graveyards)
    end)

    :ok
  end
end
