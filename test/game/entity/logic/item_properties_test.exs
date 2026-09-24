defmodule ThistleTea.Game.Entity.Logic.ItemPropertiesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.ItemProperties

  describe "select/2" do
    test "normalizes weights and handles both roll endpoints" do
      entries = [{1182, 2.0}, {1183, 6.0}]
      assert ItemProperties.select(entries, 0) == 1182
      assert ItemProperties.select(entries, 0.25) == 1182
      assert ItemProperties.select(entries, 0.25001) == 1183
      assert ItemProperties.select(entries, 1) == 1183
    end

    test "skips invalid weights and handles missing tables" do
      entries = [{1, 0.0}, {2, -1.0}, {3, 0.000001}, {4, 100.1}, {5, 0.5}]
      assert ItemProperties.select(entries, 0) == 5
      assert ItemProperties.select(entries, 1) == 5
      assert ItemProperties.select([], 0.5) == nil
      assert ItemProperties.select([{1, 0}], 0.5) == nil
    end
  end
end
