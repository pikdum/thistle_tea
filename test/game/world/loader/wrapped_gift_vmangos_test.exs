defmodule ThistleTea.Game.World.Loader.WrappedGiftVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.World.Loader.Item

  @moduletag :vmangos_db

  describe "get_template/1" do
    test "loads all retail paper-to-gift mappings from seed data" do
      for {paper, gift} <- [
            {5042, 5043},
            {5048, 5044},
            {17_303, 17_302},
            {17_304, 17_305},
            {17_307, 17_308},
            {21_830, 21_831}
          ] do
        assert %ItemTemplate{flags: 512, wrapped_gift: ^gift} = Item.get_template(paper)
        assert %ItemTemplate{flags: 512, stackable: 1, wrapped_gift: 0} = Item.get_template(gift)
      end
    end
  end
end
