defmodule ThistleTea.Game.World.SpawnPool.CatalogTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.SpawnPool.Catalog
  alias ThistleTea.Game.World.SpawnPool.Selection

  @moduletag :vmangos_db

  describe "VMangos pool loading" do
    test "expands Hogger's template pool to its five spawn rows" do
      members =
        1270
        |> Catalog.root_members()
        |> Enum.filter(&(&1.kind == :creature))

      assert Enum.map(members, & &1.id) |> Enum.sort() == [80_531, 80_731, 81_027, 81_028, 81_029]
      assert Enum.all?(members, &(Catalog.group_for(:creature, &1.id) == {:pool, 1270}))
      assert Catalog.data().pools[1270].max_limit == 1
    end

    test "selects a configured number of resource nodes" do
      catalog = Catalog.data()
      available = available_members(4303)

      selection = Selection.initialize(4303, catalog, available)

      assert MapSet.size(selection.leaves) == 37
    end

    test "expands a selected dungeon pack child pool" do
      catalog = Catalog.data()
      available = available_members(4294)

      selection = Selection.initialize(4294, catalog, available)

      assert [%{kind: :pool}] = selection.direct[4294]
      assert MapSet.size(selection.leaves) in 3..4
    end
  end

  defp available_members(root_id) do
    root_id
    |> Catalog.root_members()
    |> MapSet.new(&{&1.kind, &1.id})
  end
end
