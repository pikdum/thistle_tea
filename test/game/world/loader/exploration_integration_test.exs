defmodule ThistleTea.Game.World.Loader.ExplorationIntegrationTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.Exploration

  describe "load_areas/0" do
    @tag :dbc_db
    test "caches AreaTable exploration metadata" do
      Exploration.load_areas()

      assert %AreaTable{area_bit: 707, exploration_level: 10, name: "Orgrimmar"} = Exploration.area(1637)
    end
  end

  describe "load_base_xp/0" do
    @tag :vmangos_db
    test "caches VMangos exploration XP" do
      Exploration.load_base_xp()

      assert Exploration.base_xp(10) > 0
    end
  end
end
