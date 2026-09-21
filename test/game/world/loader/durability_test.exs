defmodule ThistleTea.Game.World.Loader.DurabilityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Buyback
  alias ThistleTea.Game.Entity.Logic.Durability, as: DurabilityLogic
  alias ThistleTea.Game.World.Loader.Durability

  @moduletag :dbc_db

  describe "load_all/1" do
    test "matches the native worn shortsword sale tooltip" do
      table = :ets.new(__MODULE__, [:set])
      Durability.load_all(table)

      template = %ItemTemplate{
        entry: 25,
        item_level: 2,
        class: 2,
        subclass: 7,
        quality: 1,
        max_durability: 20,
        sell_price: 7
      }

      item = Item.build(template, 1) |> DurabilityLogic.lose(:points, 2)
      assert item.item.durability == 18
      assert Durability.sale_penalty(item, table) == 2
      assert {:ok, 5} = Buyback.sale_price(item, 1, &Durability.sale_penalty(&1, table))
    end

    test "loads actual weapon and armor repair factors" do
      table = :ets.new(__MODULE__, [:set])
      assert :ok = Durability.load_all(table)

      for {class, subclass} <- [{2, 7}, {4, 4}, {4, 6}] do
        item =
          Item.build(
            %ItemTemplate{item_level: 50, quality: 2, class: class, subclass: subclass, max_durability: 100},
            1
          )

        damaged = DurabilityLogic.lose(item, :percent, 10)
        assert Durability.cost(item, 1.0, table) == 0
        cost = Durability.cost(damaged, 1.0, table)
        assert is_integer(cost) and cost > 0
        assert Durability.cost(damaged, 0.9, table) == max(round(cost * 0.8999999761581421), 1)
      end
    end
  end
end
