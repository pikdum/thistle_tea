defmodule ThistleTea.Game.World.Loader.ItemPropertyDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Item.ItemProperty
  alias ThistleTea.Game.World.Loader.ItemProperty, as: ItemPropertyLoader

  @moduletag :dbc_db

  describe "load_definitions/0" do
    test "loads vanilla suffix names and their three enchantments" do
      ItemPropertyLoader.load_definitions()
      assert %ItemProperty{suffix: "of the Bear", enchantments: [72, 69, 0]} = ItemPropertyLoader.get(1182)
      assert %ItemProperty{suffix: "of Stamina", enchantments: [72, 0, 0]} = ItemPropertyLoader.get(19)
      assert ItemPropertyLoader.get(0) == nil
    end
  end
end
