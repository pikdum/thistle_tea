defmodule ThistleTea.Game.World.Loader.TaxiDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Taxi.Path
  alias ThistleTea.Game.World.Loader.Taxi

  @moduletag :dbc_db

  describe "load_paths/0" do
    test "loads route metadata and ordered spline nodes" do
      assert %Path{} = path = Enum.find(Taxi.load_paths(), &(&1.id == 6))
      assert path.source_node_id == 2
      assert path.destination_node_id == 4
      assert path.cost == 110
      assert Enum.map(path.nodes, & &1.index) == Enum.to_list(0..27)
    end
  end

  describe "load_spell_path_ids/0" do
    test "finds SEND_TAXI spell routes" do
      assert Taxi.load_spell_path_ids() == [315, 316, 472, 494, 495, 496]
    end
  end
end
