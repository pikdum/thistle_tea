defmodule ThistleTea.Game.Entity.Logic.Auction.InventoryTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Auction
  alias ThistleTea.Game.Entity.Data.Auction.Book
  alias ThistleTea.Game.Entity.Data.Auction.Change
  alias ThistleTea.Game.Entity.Data.Auction.House
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Auction.Inventory, as: AuctionInventory
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast

  setup [:inventory]

  describe "validate_sale/5" do
    test "accepts carried items and rejects bound, conjured, and temporary items", context do
      assert validate(context, context.item) == :ok

      for template <- [
            %ItemTemplate{entry: 25, bonding: 1},
            %ItemTemplate{entry: 25, flags: 2},
            %ItemTemplate{entry: 25, duration: 60},
            %ItemTemplate{entry: 25, duration: -60}
          ] do
        item = Item.build(template, 100, owner: 1)
        assert {:error, _reason} = validate(context, item)
      end
    end

    test "rejects bank, foreign, and active cast items", context do
      bank = %{context.character | player: %Player{bank1: 100, coinage: 100}}
      assert {:error, :item_not_found} = validate(%{context | character: bank}, context.item)
      foreign = %{context.item | item: %{context.item.item | owner: 2}}
      assert {:error, :dont_own_that_item} = validate(context, foreign)

      casting = %Cast{spell: %Spell{}, cast_item_guid: 100}
      caster = %{context.character | internal: %{context.character.internal | casting: casting}}
      assert {:error, :item_locked} = validate(%{context | character: caster}, context.item)
    end

    test "rejects nonempty bags", context do
      bag = Item.build(%ItemTemplate{entry: 26, container_slots: 4}, 100, owner: 1)
      bag = %{bag | container: %{bag.container | slot_1: 101}}
      assert {:error, :can_only_do_with_empty_bags} = validate(context, bag)
    end
  end

  describe "plan/3" do
    test "detaches the exact stack and charges the deposit in one plan", context do
      assert {:ok, changes} = AuctionInventory.plan(context.character, context.sale, context.lookup)
      assert changes.player.inv1 in [nil, 0]
      assert changes.player.coinage == 85
      assert ChangeSet.destroyed_items(changes) == []
      assert context.character.player.inv1 == 100
      assert context.lookup.(100) == context.item
    end

    test "rejects a missing item or fee without producing a partial change", context do
      assert {:error, :item_not_found} = AuctionInventory.plan(context.character, context.sale, fn _ -> nil end)
      poor = %{context.character | player: %{context.character.player | coinage: 14}}
      assert {:error, :not_enough_money} = AuctionInventory.plan(poor, context.sale, context.lookup)
    end

    test "reserves bid money without moving inventory", context do
      bid = %{context.sale | action: :bid_placed, cost: 75}
      assert {:ok, changes} = AuctionInventory.plan(context.character, bid, context.lookup)
      assert changes.player.inv1 == 100
      assert changes.player.coinage == 25
      assert ChangeSet.changed_items(changes) == []
    end
  end

  defp inventory(_context) do
    item = Item.build(%ItemTemplate{entry: 25, sell_price: 100}, 100, owner: 1, stack_count: 3)
    character = %Character{object: %Object{guid: 1}, player: %Player{inv1: 100, coinage: 100}, internal: %Internal{}}

    auction = %Auction{
      id: 1,
      house: %House{id: 1, market: :alliance, deposit_percent: 5, cut_percent: 5},
      item: item,
      owner: 1,
      owner_account: 1,
      start_bid: 100,
      buyout: 1_000,
      deposit: 15,
      created_at: 0,
      expires_at: 7_200_000
    }

    %{
      item: item,
      character: character,
      lookup: fn guid -> if guid == 100, do: item end,
      sale: %Change{book: %Book{}, auction: auction, action: :started, cost: 15}
    }
  end

  defp validate(context, item) do
    AuctionInventory.validate_sale(context.character, item, 0, fn guid -> if guid == 100, do: item end, fn _ -> nil end)
  end
end
