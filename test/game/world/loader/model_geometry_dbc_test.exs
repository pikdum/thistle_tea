defmodule ThistleTea.Game.World.Loader.ModelGeometryDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DBC
  alias ThistleTea.Game.World.Loader.ModelGeometry
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load_all/0" do
    test "reads Vanilla collision height from column 15 and caches display geometry" do
      model = DBC.get!(CreatureModelData, DBC.get!(CreatureDisplayInfo, 50).model)
      assert_in_delta model.collision_height, 1.913, 0.001
      ModelGeometry.load_all()
      assert_in_delta ModelGeometry.height(50), 1.913, 0.001
    end
  end

  describe "load/1" do
    test "maps water breathing and the Forsaken extended breath passive" do
      assert Enum.any?(SpellLoader.load(5697).effects, &(&1.aura == :water_breathing))
      assert Enum.any?(SpellLoader.load(5227).effects, &(&1.aura == :water_breathing_pct and &1.base_points == 299))
    end
  end
end
