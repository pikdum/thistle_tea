defmodule ThistleTea.Game.World.System.AuctionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Auction.House
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.World.AuctionStore
  alias ThistleTea.Game.World.PostOffice
  alias ThistleTea.Game.World.System.Auction

  setup [:market]

  describe "transact/5" do
    test "commits the exact item, deposit, inventory, and recovery receipt together", context do
      {:ok, receipt} = sell(context)
      assert receipt.changes.player.inv1 in [0, nil]
      assert receipt.changes.player.coinage == 985
      assert receipt.old_counts == %{25 => 3}
      assert receipt.outgoing == [100]
      assert AuctionStore.pending(1, context.table) == receipt
      assert AuctionStore.book(context.table).auctions[1] == receipt.auction
      item = AuctionStore.item(100, context.table)
      assert item.item.owner == 0
      assert item.item.stack_count == 3
      assert item.object.guid == context.item.object.guid
      assert item.item.durability == context.item.item.durability
      assert item.item.enchantment == context.item.item.enchantment
    end

    test "rejects stale callers, missing items, and deposits without partial changes", context do
      :ets.delete(context.owners, 1)
      assert {:error, :not_owner} = sell(context)
      :ets.insert(context.owners, {1, self()})
      poor = %{context.seller | player: %{context.seller.player | coinage: 14}}
      assert {:error, :not_enough_money} = sell(%{context | seller: poor})
      assert AuctionStore.book(context.table).auctions == %{}
      assert AuctionStore.pending(1, context.table) == nil
      assert AuctionStore.item(100, context.table) == context.item

      :ets.delete(context.table, 100)
      assert {:error, :item_not_found} = sell(context)
      assert AuctionStore.book(context.table).next_id == 1
    end

    test "retains an unapplied receipt and requires its exact acknowledgement", context do
      {:ok, receipt} = sell(context)
      assert {:error, :pending_receipt} = sell(context)
      AuctionStore.acknowledge(%{receipt | id: make_ref()}, context.table)
      assert AuctionStore.pending(1, context.table) == receipt
      AuctionStore.acknowledge(receipt, context.table)
      assert AuctionStore.pending(1, context.table) == nil
    end

    test "serializes competing buyouts and charges only the winning buyer", context do
      {:ok, sale} = sell(context)

      results =
        for guid <- [2, 3] do
          Task.async(fn ->
            :ets.insert(context.owners, {guid, self()})
            buyer = buyer(guid)
            Auction.transact(buyer, context.house, {:bid, sale.auction.id, 200}, %{}, context.server)
          end)
        end
        |> Task.await_many()

      assert [receipt] = for({:ok, receipt} <- results, do: receipt)
      assert Enum.count(results, &(&1 == {:error, :item_not_found})) == 1
      assert receipt.changes.player.coinage == 800
      loser = if receipt.guid == 2, do: 3, else: 2
      assert AuctionStore.pending(loser, context.table) == nil
      assert AuctionStore.book(context.table).auctions == %{}
      assert AuctionStore.item(100, context.table).item.owner == receipt.guid
      assert {_token, [won]} = PostOffice.open(receipt.guid, self(), context.post_office)
      assert won.item_guid == 100
      assert {_token, [proceeds]} = PostOffice.open(1, self(), context.post_office)
      assert proceeds.money == 205
    end

    test "keeps mail in the outbox while the delivery boundary is unavailable", context do
      {:ok, sale} = sell(context)
      Agent.update(context.deliver, fn _ -> false end)
      assert {:ok, _receipt} = bid(context, 2, sale.auction.id, 200)
      assert length(AuctionStore.deliveries(context.table)) == 2
      assert AuctionStore.item(100, context.table).item.owner == 2
      assert {_token, []} = PostOffice.open(2, self(), context.post_office)

      Agent.update(context.deliver, fn _ -> true end)
      assert :ok = Auction.settle(context.server)
      assert AuctionStore.deliveries(context.table) == []
      assert {_token, [won]} = PostOffice.open(2, self(), context.post_office)
      assert won.item_guid == 100
    end
  end

  describe "restart recovery" do
    test "restores the book and receipts and expires a bid exactly once", context do
      {:ok, sale} = sell(context)
      {:ok, bid} = bid(context, 2, sale.auction.id, 100)
      stop_supervised!(Auction)
      server = start_supervised!({Auction, context.opts})
      assert AuctionStore.pending(1, context.table) == sale
      assert AuctionStore.pending(2, context.table) == bid
      assert {[listing], 1} = Auction.list(context.house, {:owned, 1, 0}, server)
      assert listing.bid == 100

      Agent.update(context.clock, fn _ -> listing.expires_at end)
      assert :ok = Auction.settle(server)
      assert Auction.list(context.house, {:owned, 1, 0}, server) == {[], 0}
      assert {_token, [won]} = PostOffice.open(2, self(), context.post_office)
      assert won.item_guid == 100
      assert {_token, [proceeds]} = PostOffice.open(1, self(), context.post_office)
      assert proceeds.money == 110
      assert :ok = Auction.settle(server)
      assert {_token, [^won]} = PostOffice.open(2, self(), context.post_office)
    end

    test "retries mail already posted before an interrupted outbox acknowledgement", context do
      {:ok, sale} = sell(context)
      Agent.update(context.deliver, fn _ -> false end)
      assert {:ok, _receipt} = bid(context, 2, sale.auction.id, 200)
      deliveries = AuctionStore.deliveries(context.table)
      Enum.each(deliveries, &PostOffice.post_once(&1.key, &1.attrs, context.post_office))
      {token, [won]} = PostOffice.open(2, self(), context.post_office)
      PostOffice.acknowledge(2, token, [won.id], context.post_office)
      PostOffice.close(2, token, [], context.post_office)
      stop_supervised!(Auction)
      Agent.update(context.deliver, fn _ -> true end)
      server = start_supervised!({Auction, context.opts})
      assert :ok = Auction.settle(server)
      assert AuctionStore.deliveries(context.table) == []
      assert {_token, []} = PostOffice.open(2, self(), context.post_office)
      assert {_token, [_proceeds]} = PostOffice.open(1, self(), context.post_office)
    end
  end

  defp market(_context) do
    table = :ets.new(:auctions, [:public])
    owners = :ets.new(:owners, [:public])
    :ets.insert(owners, {1, self()})
    clock = start_supervised!({Agent, fn -> 1_000 end}, id: :clock)
    deliver = start_supervised!({Agent, fn -> true end}, id: :deliver)
    post_office = start_supervised!({PostOffice, name: nil})

    opts = [
      name: nil,
      table: table,
      now: fn -> Agent.get(clock, & &1) end,
      owner: fn guid ->
        case :ets.lookup(owners, guid) do
          [{^guid, pid}] -> pid
          [] -> nil
        end
      end,
      enchantment: fn _id -> nil end,
      notify: fn _notice -> :ok end,
      post: fn key, attrs ->
        if Agent.get(deliver, & &1), do: PostOffice.post_once(key, attrs, post_office), else: {:error, :unavailable}
      end
    ]

    item = Item.build(%ItemTemplate{entry: 25, sell_price: 100, max_durability: 80}, 100, owner: 1, stack_count: 3)
    item = %{item | item: %{item.item | durability: 17, enchantment: 123}}
    :ets.insert(table, {100, item})
    seller = %{buyer(1) | player: %Player{inv1: 100, coinage: 1_000}}

    %{
      table: table,
      owners: owners,
      clock: clock,
      deliver: deliver,
      post_office: post_office,
      opts: opts,
      server: start_supervised!({Auction, opts}),
      item: item,
      seller: seller,
      house: %House{id: 1, market: :alliance, deposit_percent: 5, cut_percent: 5}
    }
  end

  defp buyer(guid) do
    %Character{account_id: guid, object: %Object{guid: guid}, player: %Player{coinage: 1_000}, internal: %Internal{}}
  end

  defp sell(context) do
    terms = %{start_bid: 100, buyout: 200, duration_minutes: 120}
    Auction.transact(context.seller, context.house, {:sell, 100, terms}, %{25 => 3}, context.server)
  end

  defp bid(context, guid, id, amount) do
    :ets.insert(context.owners, {guid, self()})
    Auction.transact(buyer(guid), context.house, {:bid, id, amount}, %{}, context.server)
  end
end
