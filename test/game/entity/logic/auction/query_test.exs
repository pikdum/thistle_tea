defmodule ThistleTea.Game.Entity.Logic.Auction.QueryTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Auction.Actor
  alias ThistleTea.Game.Entity.Data.Auction.Book
  alias ThistleTea.Game.Entity.Data.Auction.House
  alias ThistleTea.Game.Entity.Data.Auction.Query
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemProperty
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Auction
  alias ThistleTea.Game.Entity.Logic.Auction.Query, as: AuctionQuery

  setup [:market]

  describe "search/5" do
    test "matches an item's retained random suffix", context do
      auction = context.book.auctions[1]
      property = %ItemProperty{id: 1182, suffix: "of the Bear"}
      item = Item.build(Item.template(auction.item), auction.item.object.guid, random_property: property)
      book = %{context.book | auctions: %{1 => %{auction | item: item}}}

      assert {[_auction], 1} = AuctionQuery.search(book, context.house, %Query{name: "OF THE BEAR"}, 0)
      assert {[], 0} = AuctionQuery.search(book, context.house, %Query{name: "eagle"}, 0)
    end

    test "filters localized names, categories, robes, minimum quality, and level bounds", context do
      query = %Query{name: "silk", class: 4, subclass: 1, inventory_type: 5, quality: 2, level_min: 10, level_max: 30}
      assert {[_auction], 1} = AuctionQuery.search(context.book, context.house, query, 0)

      for query <- [
            %{query | name: "axe"},
            %{query | class: 2},
            %{query | subclass: 2},
            %{query | inventory_type: 1},
            %{query | quality: 4},
            %{query | level_min: 21},
            %{query | level_min: 0, level_max: 19}
          ] do
        assert {[], 0} = AuctionQuery.search(context.book, context.house, query, 0)
      end

      query = %Query{name: "eagle"}

      assert {[_auction], 1} =
               AuctionQuery.search(context.book, context.house, query, 0,
                 item_name: fn _ -> "Silk Robe of the Eagle" end
               )
    end

    test "checks usability only when requested", context do
      rejected = fn _ -> false end
      assert {[_auction], 1} = AuctionQuery.search(context.book, context.house, %Query{}, 0, usable: rejected)
      assert {[], 0} = AuctionQuery.search(context.book, context.house, %Query{usable?: true}, 0, usable: rejected)
    end

    test "excludes foreign markets and expired listings", context do
      assert {[], 0} = AuctionQuery.search(context.book, %{context.house | market: :horde}, %Query{}, 0)
      assert {[], 0} = AuctionQuery.search(context.book, context.house, %Query{}, 7_200_000)
      assert {[_auction], 1} = AuctionQuery.search(context.book, %{context.house | id: 3}, %Query{}, 0)
    end

    test "sorts by buyout then identity and limits pages to fifty rows", context do
      auction = context.book.auctions[1]
      auctions = Map.new(1..55, &{&1, %{auction | id: &1, buyout: 1_000 - &1}})
      book = %{context.book | auctions: auctions}
      assert {first, 55} = AuctionQuery.search(book, context.house, %Query{}, 0)
      assert Enum.map(first, & &1.id) == Enum.to_list(55..6//-1)
      assert {second, 55} = AuctionQuery.search(book, context.house, %Query{offset: 50}, 0)
      assert Enum.map(second, & &1.id) == [5, 4, 3, 2, 1]
      assert {[], 55} = AuctionQuery.search(book, context.house, %Query{offset: 55}, 0)
    end
  end

  describe "owned/5 and bids/6" do
    test "projects owner and bidder lists with requested outbid refreshes", context do
      assert {[_auction], 1} = AuctionQuery.owned(context.book, context.house, 1, 0, 0)
      assert {[], 0} = AuctionQuery.owned(context.book, context.house, 2, 0, 0)
      buyer = %Actor{guid: 2, account_id: 2, money: 1_000}
      {:ok, change} = Auction.bid(context.book, buyer, context.house, 1, 100, 0)
      assert {[_auction], 1} = AuctionQuery.bids(change.book, context.house, 2, [1, 1, 99], 0, 0)
      assert {[_auction], 1} = AuctionQuery.bids(change.book, context.house, 3, [1], 0, 0)
      assert {[], 0} = AuctionQuery.bids(change.book, context.house, 3, [], 0, 0)
      assert {[], 0} = AuctionQuery.bids(change.book, %{context.house | market: :neutral}, 2, [1], 0, 0)
    end
  end

  defp market(_context) do
    owner = %Actor{guid: 1, account_id: 1, money: 100}
    house = %House{id: 1, market: :alliance, deposit_percent: 5, cut_percent: 5}

    template = %ItemTemplate{
      entry: 25,
      name: "Silk Robe",
      class: 4,
      subclass: 1,
      inventory_type: 20,
      quality: 3,
      required_level: 20
    }

    item = Item.build(template, 100, owner: 1)

    {:ok, change} =
      Auction.sell(%Book{}, owner, house, item, %{start_bid: 100, buyout: 1_000, duration_minutes: 120}, 0)

    %{book: change.book, house: house}
  end
end
