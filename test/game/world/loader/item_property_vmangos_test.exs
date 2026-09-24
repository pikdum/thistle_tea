defmodule ThistleTea.Game.World.Loader.ItemPropertyVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.ItemProperty, as: PropertyLoader

  @moduletag :vmangos_db

  describe "load_tables/0" do
    test "loads Skullcrusher Mace's weighted property choices" do
      PropertyLoader.load_tables()
      assert ItemLoader.get_template(1608).random_property == 5269
      choices = PropertyLoader.choices(5269)
      assert {184, 0.1001} in choices
      assert length(choices) > 10
      assert Enum.all?(choices, fn {id, chance} -> id > 0 and chance > 0 and chance <= 100 end)
      assert PropertyLoader.choices(0) == []
    end
  end
end
