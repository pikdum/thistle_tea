defmodule ThistleTea.Game.World.Loader.CreatureLinkTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Creature.CreatureLink
  alias ThistleTea.Game.World.Loader.CreatureLink, as: CreatureLinkLoader

  @rajaxx 15_341
  @captain 15_385
  @loatheb 16_011
  @maggot 16_056

  describe "build/3" do
    test "indexes direct links by slave and by master" do
      catalog = CreatureLinkLoader.build([{1, 13_991, 13_990, 3203}, {1, 13_992, 13_990, 3203}], [], [])

      assert %CreatureLink{slave: 13_991, master: 13_990, flags: 3203} = catalog[{1, 13_991}]
      assert [13_991, 13_992] = catalog |> Map.fetch!({1, {:slaves, 13_990}}) |> Enum.map(& &1.slave) |> Enum.sort()
    end

    test "ties a templated slave to the nearest master in range, or to the map's only master" do
      templates = [
        %{entry: @captain, map: 509, master_entry: @rajaxx, flag: 1, search_range: 150},
        %{entry: @maggot, map: 533, master_entry: @loatheb, flag: 3072, search_range: 0}
      ]

      spawns = [
        {1, @rajaxx, 509, 0.0, 0.0},
        {2, @rajaxx, 509, 100.0, 0.0},
        {3, @captain, 509, 90.0, 0.0},
        {4, @captain, 509, 400.0, 0.0},
        {5, @loatheb, 533, 0.0, 0.0},
        {6, @maggot, 533, 900.0, 900.0}
      ]

      catalog = CreatureLinkLoader.build([], templates, spawns)

      assert %CreatureLink{master: 2, flags: 1} = catalog[{509, 3}]
      refute Map.has_key?(catalog, {509, 4})
      assert %CreatureLink{master: 5, flags: 3072} = catalog[{533, 6}]
    end

    test "leaves a zero-range template unlinked when its master spawns more than once" do
      templates = [%{entry: @maggot, map: 533, master_entry: @loatheb, flag: 3072, search_range: 0}]
      spawns = [{5, @loatheb, 533, 0.0, 0.0}, {7, @loatheb, 533, 50.0, 0.0}, {6, @maggot, 533, 1.0, 0.0}]

      assert CreatureLinkLoader.build([], templates, spawns) == %{}
    end

    test "prefers a spawn's own link over its entry's template" do
      templates = [%{entry: @captain, map: 509, master_entry: @rajaxx, flag: 1, search_range: 150}]
      spawns = [{1, @rajaxx, 509, 0.0, 0.0}, {3, @captain, 509, 10.0, 0.0}]

      catalog = CreatureLinkLoader.build([{509, 3, 9, 2}], templates, spawns)

      assert %CreatureLink{master: 9, flags: 2} = catalog[{509, 3}]
      refute Map.has_key?(catalog, {509, {:slaves, 1}})
    end
  end
end
