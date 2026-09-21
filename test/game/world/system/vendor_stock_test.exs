defmodule ThistleTea.Game.World.System.VendorStockTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.VendorItem
  alias ThistleTea.Game.Entity.Data.VendorStock.Receipt
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.World.System.VendorStock
  alias ThistleTea.Game.World.VendorStockStore
  alias ThistleTea.Game.WorldRef

  setup [:merchant]

  describe "purchase/3" do
    test "serializes competing buyers of the last item and commits only the winner", context do
      results =
        for guid <- [1, 2] do
          Task.async(fn ->
            :ets.insert(context.owners, {guid, self()})
            VendorStock.purchase(context.world, receipt(context, guid), context.server)
          end)
        end
        |> Task.await_many()

      assert [won] = for({:ok, receipt} <- results, do: receipt)
      assert Enum.count(results, &(&1 == {:error, :item_already_sold})) == 1
      assert won.available == 0
      assert won.changes.player.coinage == 90
      assert VendorStockStore.pending(won.guid, context.table) == won
      assert [{_, %Item{item: %{owner: owner}}}] = :ets.lookup(context.table, won.guid + 100)
      assert owner == won.guid
      loser = if won.guid == 1, do: 2, else: 1
      assert VendorStockStore.pending(loser, context.table) == nil
      assert :ets.lookup(context.table, loser + 100) == []
      assert [%{available: 0}] = listing(context)
    end

    test "requires the player owner and an exact receipt acknowledgement", context do
      offer = receipt(context, 1)
      assert {:error, :not_owner} = VendorStock.purchase(context.world, offer, context.server)
      :ets.insert(context.owners, {1, self()})
      assert {:ok, bought} = VendorStock.purchase(context.world, offer, context.server)
      assert {:error, :pending_receipt} = VendorStock.purchase(context.world, offer, context.server)
      VendorStockStore.acknowledge(%{bought | id: make_ref()}, context.table)
      assert VendorStockStore.pending(1, context.table) == bought
      VendorStockStore.acknowledge(bought, context.table)
      assert VendorStockStore.pending(1, context.table) == nil
    end

    test "keeps stock and recovery receipts across coordinator restart", context do
      :ets.insert(context.owners, {1, self()})
      {:ok, bought} = VendorStock.purchase(context.world, receipt(context, 1), context.server)
      stop_supervised!(VendorStock)
      server = start_supervised!({VendorStock, context.opts})
      context = %{context | server: server}
      assert [%{available: 0}] = listing(context)
      assert VendorStockStore.pending(1, context.table) == bought
      Agent.update(context.clock, fn _ -> 10_999 end)
      assert [%{available: 0}] = listing(context)
      Agent.update(context.clock, fn _ -> 11_000 end)
      assert [%{available: 1}] = listing(context)
      assert VendorStockStore.stock({context.world, 500, 25}, context.table) == nil
      assert VendorStockStore.pending(1, context.table) == bought
    end
  end

  describe "list/4 and clear_world/2" do
    test "isolates merchant spawns and world copies and clears only the expired copy", context do
      :ets.insert(context.owners, {1, self()})
      {:ok, bought} = VendorStock.purchase(context.world, receipt(context, 1), context.server)
      other = WorldRef.open(0)
      assert [%{available: 1}] = VendorStock.list(other, 500, [context.item], context.server)
      assert [%{available: 1}] = VendorStock.list(context.world, 501, [context.item], context.server)
      assert [%{available: 0}] = listing(context)
      :ok = VendorStock.clear_world(other, context.server)
      assert [%{available: 0}] = listing(context)
      :ok = VendorStock.clear_world(context.world, context.server)
      assert [%{available: 1}] = listing(context)
      assert VendorStockStore.pending(1, context.table) == bought
      assert :ets.lookup(context.table, 101) != []
    end
  end

  defp merchant(_context) do
    table = :ets.new(:stock, [:public])
    owners = :ets.new(:owners, [:public])
    clock = start_supervised!({Agent, fn -> 1_000 end})

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
      random: fn -> 100 end,
      population: fn -> 1 end
    ]

    %{
      table: table,
      owners: owners,
      clock: clock,
      opts: opts,
      server: start_supervised!({VendorStock, opts}),
      world: %WorldRef{map_id: 33, instance_id: 1},
      item: %VendorItem{index: 1, template: %ItemTemplate{entry: 25, buy_count: 1}, max_count: 1, restock_seconds: 10}
    }
  end

  defp listing(context), do: VendorStock.list(context.world, 500, [context.item], context.server)

  defp receipt(context, guid) do
    item = Item.build(context.item.template, guid + 100, owner: guid)
    {:ok, changes} = %Player{coinage: 90} |> Batch.new() |> Batch.add(item) |> Inventory.plan(fn _ -> nil end)

    %Receipt{
      id: make_ref(),
      guid: guid,
      changes: changes,
      old_counts: %{25 => 0},
      vendor_guid: 500,
      vendor_item: context.item,
      count: 1,
      available: nil,
      position: {255, 23}
    }
  end
end
