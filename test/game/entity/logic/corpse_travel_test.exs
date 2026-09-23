defmodule ThistleTea.Game.Entity.Logic.CorpseTravelTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Dungeon
  alias ThistleTea.Game.Entity.Logic.CorpseTravel

  setup [:build_dungeons]

  describe "destination/3" do
    test "accepts the corpse dungeon and its parent entrances", %{dungeons: dungeons} do
      assert CorpseTravel.destination(3, 3, dungeons) == {:ok, 3}
      assert CorpseTravel.destination(3, 2, dungeons) == {:ok, 3}
      assert CorpseTravel.destination(3, 1, dungeons) == {:ok, 3}
      assert CorpseTravel.destination(2, 3, dungeons) == {:error, :wrong_dungeon}
      assert CorpseTravel.destination(nil, 1, dungeons) == {:error, :wrong_dungeon}
      assert CorpseTravel.destination(0, 1, dungeons) == {:error, :wrong_dungeon}
    end

    test "stops on malformed cycles and unknown parents", %{dungeons: dungeons} do
      cycle = Map.put(dungeons, 1, %Dungeon{map_id: 1, parent_map: 3})
      assert CorpseTravel.destination(3, 99, cycle) == {:error, :wrong_dungeon}
      missing = Map.delete(dungeons, 2)
      assert CorpseTravel.destination(3, 1, missing) == {:error, :wrong_dungeon}
    end
  end

  describe "entrance/3" do
    test "projects an outside entrance only from another map", %{dungeons: dungeons} do
      assert CorpseTravel.entrance(3, 0, dungeons) == {0, 10.0, 20.0}
      assert CorpseTravel.entrance(3, 3, dungeons) == nil
      assert CorpseTravel.entrance(0, 1, dungeons) == nil
      assert CorpseTravel.entrance(1, 0, dungeons) == nil
    end
  end

  defp build_dungeons(_context) do
    %{
      dungeons: %{
        1 => %Dungeon{map_id: 1},
        2 => %Dungeon{map_id: 2, parent_map: 1},
        3 => %Dungeon{map_id: 3, parent_map: 2, ghost_entrance: {0, 10.0, 20.0}}
      }
    }
  end
end
