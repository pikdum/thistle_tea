defmodule ThistleTea.Game.World.Loader.SpellAppearanceVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Model
  alias ThistleTea.Game.World.Loader.SpellAppearance

  @moduletag :vmangos_db

  describe "creature_model/1" do
    test "loads the creature's display scale and equipment independently of spell DBC rows" do
      assert %Model{display_id: 4617, scale: 1.0, equipment: [nil, nil, nil]} = SpellAppearance.creature_model(5946)

      assert %Model{display_id: 7550, equipment: [%ItemTemplate{entry: 2711}, nil, nil]} =
               SpellAppearance.creature_model(531)
    end
  end
end
