defmodule ThistleTea.Game.Entity.Logic.AuctionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Auction.Actor
  alias ThistleTea.Game.Entity.Data.Auction.Book
  alias ThistleTea.Game.Entity.Data.Auction.House
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Auction
  alias ThistleTea.Game.Entity.Logic.Mail

  setup [:market]

  describe "deposit/3" do
    test "uses house rates, stack quantity, and two-hour increments", context do
      assert Auction.deposit(context.house, context.item, 120) == 15
      assert Auction.deposit(context.house, context.item, 480) == 60
      assert Auction.deposit(context.house, context.item, 1_440) == 180
      assert Auction.deposit(context.neutral, context.item, 120) == 75
      assert Auction.deposit(context.neutral, context.item, 1_440) == 900

      worthless = Item.build(%ItemTemplate{entry: 1, sell_price: 0}, 1, owner: 10)
      assert Auction.deposit(context.house, worthless, 120) == 0
    end
  end

  describe "sell/6" do
    test "escrows an item and captures the original house fees", context do
      assert {:ok, change} = sell(context)
      assert change.cost == 15
      assert change.book.next_id == 2
      assert change.auction.id == 1
      assert change.auction.expires_at == 7_200_000
      assert change.auction.item.item.owner == 0
      assert change.auction.item.item.contained == 0
      assert change.auction.house == context.house
      assert change.deliveries == []
      assert Auction.next_expiration(change.book) == 7_200_000

      assert {:error, :item_not_found} = sell(%{context | book: change.book})
    end

    test "rejects invalid terms, ownership, and insufficient funds", context do
      for duration <- [0, 1, 119, 121, 360, 2_880] do
        assert {:error, :invalid_duration} = sell(context, %{duration_minutes: duration})
      end

      for price <- [-1, 0, 2_000_000_001, 1.5] do
        assert {:error, :invalid_price} = sell(context, %{start_bid: price})
      end

      assert {:error, :higher_bid} = sell(context, %{buyout: 99})
      assert {:error, :not_enough_money} = sell(%{context | owner: %{context.owner | money: 14}})
      assert {:error, :item_not_found} = sell(%{context | owner: %{context.owner | guid: 11}})
      assert context.book == %Book{}
    end
  end

  describe "bid/6" do
    setup [:listed]

    test "enforces ownership, linked markets, expiry, and funds", context do
      assert {:error, :bid_own} = bid(context, context.owner, 100)
      assert {:error, :bid_own} = bid(context, %{context.buyer | account_id: context.owner.account_id}, 100)
      assert {:error, :bid_increment} = bid(context, context.buyer, 99)
      assert {:error, :not_enough_money} = bid(context, %{context.buyer | money: 99}, 100)
      assert {:error, :item_not_found} = Auction.bid(context.book, context.buyer, context.neutral, 1, 100, 0)
      assert {:error, :item_not_found} = Auction.bid(context.book, context.buyer, context.house, 1, 100, 7_200_000)

      linked_house = %{context.house | id: 2, cut_percent: 15}
      assert {:ok, change} = Auction.bid(context.book, context.buyer, linked_house, 1, 100, 0)
      assert change.auction.house.cut_percent == 5
    end

    test "reserves the first bid and charges only a bidder's increase", context do
      assert {:ok, first} = bid(context, context.buyer, 199)
      assert first.cost == 199
      assert first.deliveries == []
      assert Auction.increment(first.auction) == 5

      context = %{context | book: first.book}
      assert {:error, {:higher_bid, _auction}} = bid(context, context.buyer, 199)
      assert {:error, :bid_increment} = bid(context, context.buyer, 203)
      assert {:ok, raised} = bid(context, %{context.buyer | money: 5}, 204)
      assert raised.cost == 5
      assert raised.deliveries == []
    end

    test "refunds an outbid player without sharing repeated refund identifiers", context do
      {:ok, first} = bid(context, context.buyer, 100)
      {:ok, second} = bid(%{context | book: first.book}, context.other, 105)
      assert [refund] = second.deliveries
      assert refund.attrs.money == 100
      assert refund.attrs.receiver == context.buyer.guid
      assert refund.attrs.subject == "25:0:0"

      {:ok, third} = bid(%{context | book: second.book}, context.buyer, 110)
      {:ok, fourth} = bid(%{context | book: third.book}, context.other, 115)
      assert [later_refund] = fourth.deliveries
      refute later_refund.key == refund.key
      assert later_refund.attrs.money == 110
    end

    test "buyout clamps the price and settles item, deposit, cut, and prior bid", context do
      {:ok, first} = bid(context, context.buyer, 100)
      assert {:ok, sold} = bid(%{context | book: first.book}, context.other, 2_000)
      assert sold.cost == 1_000
      assert sold.book.auctions == %{}
      assert [refund, won, proceeds] = sold.deliveries
      assert refund.attrs.money == 100
      assert won.item.object.guid == context.item.object.guid
      assert won.item.item.owner == context.other.guid
      assert won.item.item.stack_count == 3
      assert won.attrs.item_guid == context.item.object.guid
      assert won.attrs.subject == "25:0:1"
      assert won.attrs.body == "000000000000000A:1000:1000"
      assert proceeds.attrs.money == 965
      assert proceeds.attrs.subject == "25:0:2"
      assert proceeds.attrs.body == "000000000000001E:1000:1000:15:50"
      assert Enum.map(sold.notices, & &1.kind) == [:outbid, :sold, :won]

      for delivery <- sold.deliveries do
        mail = Mail.new(Map.put(delivery.attrs, :id, 1), 0)
        assert Mail.visible?(mail, 0)
        assert mail.stationery == 62
        assert mail.sender_type == :auction
      end
    end

    test "the current bidder pays only the balance to buy out", context do
      {:ok, first} = bid(context, context.buyer, 900)
      assert {:ok, sold} = bid(%{context | book: first.book}, %{context.buyer | money: 100}, 1_000)
      assert sold.cost == 100
      assert length(sold.deliveries) == 2
      assert {:error, :item_not_found} = bid(%{context | book: sold.book}, context.other, 1_000)
    end
  end

  describe "cancel/5" do
    setup [:listed]

    test "returns unsold items and forfeits the deposit", context do
      assert {:ok, canceled} = Auction.cancel(context.book, context.owner, context.house, 1, 0)
      assert canceled.cost == 0
      assert canceled.book.auctions == %{}
      assert [returned] = canceled.deliveries
      assert returned.attrs.subject == "25:0:5"
      assert returned.attrs.money == 0
      assert returned.item.item.owner == context.owner.guid
      assert {:error, :not_owner} = Auction.cancel(context.book, context.buyer, context.house, 1, 0)
    end

    test "requires the sale cut and refunds the active bid", context do
      {:ok, first} = bid(context, context.buyer, 500)
      poor = %{context.owner | money: 24}
      assert {:error, :not_enough_money} = Auction.cancel(first.book, poor, context.house, 1, 0)

      assert {:ok, canceled} = Auction.cancel(first.book, context.owner, context.house, 1, 0)
      assert canceled.cost == 25
      assert [refund, returned] = canceled.deliveries
      assert refund.attrs.money == 500
      assert refund.attrs.subject == "25:0:4"
      assert returned.item.item.owner == context.owner.guid
      assert [%{recipient: 20, kind: :removed}] = canceled.notices
    end
  end

  describe "expire/2" do
    test "settles sold and unsold auctions once at their deadline", context do
      {:ok, first} = sell(context)
      other_item = %{context.item | object: %{context.item.object | guid: 101}}
      {:ok, second} = sell(%{context | book: first.book, item: other_item}, %{buyout: 0})
      {:ok, bid} = Auction.bid(second.book, context.buyer, context.house, 2, 100, 0)
      assert Auction.expire(bid.book, 7_199_999).book == bid.book

      expired = Auction.expire(bid.book, 7_200_000)
      assert expired.book.auctions == %{}
      assert [returned, won, proceeds] = expired.deliveries
      assert returned.attrs.subject == "25:0:3"
      assert returned.item.item.owner == context.owner.guid
      assert won.item.object.guid == 101
      assert proceeds.attrs.money == 110
      assert Auction.expire(expired.book, 7_200_001).deliveries == []
      assert Auction.next_expiration(expired.book) == nil
    end
  end

  defp market(_context) do
    %{
      book: %Book{},
      owner: %Actor{guid: 10, account_id: 1, money: 10_000},
      buyer: %Actor{guid: 20, account_id: 2, money: 10_000},
      other: %Actor{guid: 30, account_id: 3, money: 10_000},
      house: %House{id: 1, market: :alliance, deposit_percent: 5, cut_percent: 5},
      neutral: %House{id: 7, market: :neutral, deposit_percent: 25, cut_percent: 15},
      item: Item.build(%ItemTemplate{entry: 25, sell_price: 100}, 100, owner: 10, stack_count: 3)
    }
  end

  defp listed(context) do
    {:ok, change} = sell(context)
    %{book: change.book}
  end

  defp sell(context, overrides \\ %{}) do
    terms = Map.merge(%{start_bid: 100, buyout: 1_000, duration_minutes: 120}, overrides)
    Auction.sell(context.book, context.owner, context.house, context.item, terms, 0)
  end

  defp bid(context, actor, price), do: Auction.bid(context.book, actor, context.house, 1, price, 0)
end
