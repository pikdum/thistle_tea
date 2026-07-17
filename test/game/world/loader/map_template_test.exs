defmodule ThistleTea.Game.World.Loader.MapTemplateTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.MapTemplate

  setup do
    table = :ets.new(:map_template_test, [:set])
    :ets.insert(table, [{0, 0}, {33, 1}, {249, 2}, {30, 3}])
    %{table: table}
  end

  describe "map classification" do
    test "derives dungeons, raids, and battlegrounds from map_type", %{table: table} do
      refute MapTemplate.dungeon?(table, 0)
      assert MapTemplate.dungeon?(table, 33)
      assert MapTemplate.dungeon?(table, 249)
      refute MapTemplate.battleground?(table, 249)
      assert MapTemplate.battleground?(table, 30)
    end
  end
end
