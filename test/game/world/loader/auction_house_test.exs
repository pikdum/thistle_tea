defmodule ThistleTea.Game.World.Loader.AuctionHouseTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Auction.House
  alias ThistleTea.Game.World.Loader.AuctionHouse, as: AuctionHouseLoader

  describe "for_faction/2" do
    test "resolves city factions and group fallbacks from cached houses" do
      table = :ets.new(:auction_houses, [:set, :public])

      for id <- 1..7 do
        :ets.insert(table, {id, %House{id: id, market: :fixture, deposit_percent: 5, cut_percent: 5}})
      end

      for {faction, house} <- [{11, 1}, {55, 2}, {79, 3}, {68, 4}, {104, 5}, {29, 6}, {120, 7}, {474, 7}, {855, 7}] do
        assert AuctionHouseLoader.for_faction(%FactionTemplate{id: faction}, table).id == house
      end

      assert AuctionHouseLoader.for_faction(%FactionTemplate{id: 9999, faction_group: 2}, table).id == 1
      assert AuctionHouseLoader.for_faction(%FactionTemplate{id: 9999, faction_group: 4}, table).id == 6
      assert AuctionHouseLoader.for_faction(nil, table).id == 7
      assert AuctionHouseLoader.get(8, table) == nil
    end
  end

  describe "load_all/1" do
    @tag :dbc_db
    test "loads vanilla deposit and sale-cut percentages" do
      table = :ets.new(:auction_houses, [:set, :public])
      assert :ok = AuctionHouseLoader.load_all(table)

      for id <- 1..6 do
        assert %House{deposit_percent: 5, cut_percent: 5} = house = AuctionHouseLoader.get(id, table)
        assert house.market == if(id <= 3, do: :alliance, else: :horde)
      end

      assert %House{market: :neutral, deposit_percent: 25, cut_percent: 15} = AuctionHouseLoader.get(7, table)
    end
  end
end
