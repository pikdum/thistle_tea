defmodule ThistleTea.Game.World.SpawnPool.SelectionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.SpawnPool.Definition
  alias ThistleTea.Game.World.SpawnPool.Member
  alias ThistleTea.Game.World.SpawnPool.Selection

  describe "initialize/4" do
    test "selects one member from a singleton-limit pool" do
      catalog = catalog([pool(1, 1, [member(:creature, 10), member(:creature, 11)])])

      selection = Selection.initialize(1, catalog, available([{:creature, 10}, {:creature, 11}]), &hd/1)

      assert selection.leaves == MapSet.new([{:creature, 10}])
    end

    test "fills a multi-member limit without duplicates" do
      members = Enum.map(10..13, &member(:game_object, &1))
      catalog = catalog([pool(1, 3, members)])
      available = available(Enum.map(10..13, &{:game_object, &1}))

      selection = Selection.initialize(1, catalog, available, &hd/1)

      assert selection.leaves == MapSet.new([{:game_object, 10}, {:game_object, 11}, {:game_object, 12}])
    end

    test "expands selected child pools" do
      catalog =
        catalog(
          [
            pool(1, 1, [member(:pool, 2)]),
            pool(2, 2, [member(:creature, 20), member(:creature, 21), member(:creature, 22)])
          ],
          %{2 => 1}
        )

      selection =
        Selection.initialize(1, catalog, available([{:creature, 20}, {:creature, 21}, {:creature, 22}]), &hd/1)

      assert selection.leaves == MapSet.new([{:creature, 20}, {:creature, 21}])
      assert [%Member{kind: :pool, id: 2}] = selection.direct[1]
    end

    test "honors a guaranteed explicit chance" do
      catalog =
        catalog([
          pool(1, 1, [member(:creature, 10, 100.0), member(:creature, 11)])
        ])

      selection = Selection.initialize(1, catalog, available([{:creature, 10}, {:creature, 11}]))

      assert selection.leaves == MapSet.new([{:creature, 10}])
    end
  end

  describe "replace/6" do
    test "replaces only the triggering slot" do
      members = Enum.map(10..12, &member(:creature, &1))
      catalog = catalog([pool(1, 2, members)])
      available = available(Enum.map(10..12, &{:creature, &1}))
      selection = Selection.initialize(1, catalog, available, &hd/1)

      selection = Selection.replace(selection, 1, {:creature, 10}, catalog, available, &List.last/1)

      assert selection.leaves == MapSet.new([{:creature, 11}, {:creature, 12}])
    end

    test "replaces a selected child pool as one parent slot" do
      catalog =
        catalog(
          [
            pool(1, 1, [member(:pool, 2), member(:pool, 3)]),
            pool(2, 1, [member(:creature, 20)]),
            pool(3, 1, [member(:creature, 30)])
          ],
          %{2 => 1, 3 => 1}
        )

      available = available([{:creature, 20}, {:creature, 30}])
      selection = Selection.initialize(1, catalog, available, &hd/1)
      selection = Selection.replace(selection, 1, {:creature, 20}, catalog, available, &List.last/1)

      assert selection.leaves == MapSet.new([{:creature, 30}])
      assert [%Member{kind: :pool, id: 3}] = selection.direct[1]
    end
  end

  defp catalog(definitions, parent \\ %{}) do
    pools = Map.new(definitions, &{&1.id, &1})

    member_pool =
      definitions
      |> Enum.flat_map(fn definition ->
        definition.members
        |> Enum.reject(&(&1.kind == :pool))
        |> Enum.map(&{Member.key(&1), definition.id})
      end)
      |> Map.new()

    %{pools: pools, parent: parent, member_pool: member_pool}
  end

  defp pool(id, limit, members), do: %Definition{id: id, max_limit: limit, members: members}
  defp member(kind, id, chance \\ 0.0), do: %Member{kind: kind, id: id, chance: chance}
  defp available(members), do: MapSet.new(members)
end
