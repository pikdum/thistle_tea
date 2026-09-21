defmodule ThistleTea.Game.Player.AuctionTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Auction.Change
  alias ThistleTea.Game.Entity.Data.Auction.House
  alias ThistleTea.Game.Entity.Data.Auction.Receipt
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Auction
  alias ThistleTea.Game.World.AuctionStore
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.AuctionHouse
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.PostOffice
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:auctioneer]

  describe "house/2" do
    test "opens a nearby live vanilla auctioneer and resolves its market", context do
      assert {:ok, %House{id: 1, market: :alliance}} = Auction.house(context.state.character, context.npc)
      assert Auction.hello(context.state, context.npc) == context.state
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgAuctionHello{house_id: 1}}}

      Metadata.update(context.npc, %{faction_template: %FactionTemplate{id: 120}})
      assert {:ok, %House{id: 7, market: :neutral}} = Auction.house(context.state.character, context.npc)
    end

    test "rejects dead, ghost, remote, unflagged, and absent auctioneers", context do
      character = context.state.character
      assert Auction.house(%{character | unit: %{character.unit | health: 0}}, context.npc) == :error
      assert Auction.house(%{character | player: %{character.player | flags: 0x10}}, context.npc) == :error
      SpatialHash.update(:mobs, context.npc, WorldRef.open(1), 2.0, 0.0, 0.0)
      assert Auction.house(character, context.npc) == :error
      SpatialHash.update(:mobs, context.npc, WorldRef.open(0), 6.0, 0.0, 0.0)
      assert Auction.house(character, context.npc) == :error
      SpatialHash.update(:mobs, context.npc, WorldRef.open(0), 2.0, 0.0, 0.0)
      Metadata.update(context.npc, %{alive?: false})
      assert Auction.house(character, context.npc) == :error
      Metadata.update(context.npc, %{alive?: true, npc_flags: 0x200000})
      assert Auction.house(character, context.npc) == :error
      Metadata.delete(context.npc)
      assert Auction.house(character, context.npc) == :error
    end
  end

  describe "sell/2 and bid/2" do
    test "projects escrow, owner listings, buyout, and mail on the owning players", context do
      item =
        ItemStore.create(%ItemTemplate{entry: 25, name: "Auction fixture", sell_price: 100, stackable: 20},
          owner: context.state.guid,
          stack_count: 3
        )

      on_exit(fn -> ItemStore.delete(item.object.guid) end)
      character = %{context.state.character | player: %{context.state.character.player | inv1: item.object.guid}}
      seller = Auction.sell(%{context.state | character: character}, sale(context.npc, item.object.guid))

      assert seller.character.player.inv1 in [nil, 0]
      assert seller.character.player.coinage == 985
      assert ItemStore.get(item.object.guid).item.owner == 0
      assert AuctionStore.pending(seller.guid) == nil
      assert CharacterStore.get(seller.character.id).player.coinage == 985
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: item_guid}}}
      assert item_guid == item.object.guid

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgAuctionCommandResult{action: :started, error: :ok, auction_id: id}}}

      Auction.owned(seller, %Message.CmsgAuctionListOwnerItems{auctioneer: context.npc, offset: 0})
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgAuctionOwnerListResult{auctions: listings}}}
      assert Enum.any?(listings, &(&1.id == id))

      buyer =
        Auction.bid(context.buyer, %Message.CmsgAuctionPlaceBid{auctioneer: context.npc, auction_id: id, price: 200})

      assert buyer.character.player.coinage == 800
      assert AuctionStore.pending(buyer.guid) == nil
      assert ItemStore.get(item.object.guid).item.owner == buyer.guid
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgAuctionCommandResult{action: :bid_placed, error: :ok}}}
      assert {_token, [won]} = PostOffice.open(buyer.guid)
      assert won.item_guid == item.object.guid
      assert won.sender_type == :auction
      assert {_token, [proceeds]} = PostOffice.open(seller.guid)
      assert proceeds.money == 205
    end

    test "returns an inventory error for bound items without moving or charging them", context do
      item = ItemStore.create(%ItemTemplate{entry: 25, bonding: 1, sell_price: 100}, owner: context.state.guid)
      on_exit(fn -> ItemStore.delete(item.object.guid) end)
      character = %{context.state.character | player: %{context.state.character.player | inv1: item.object.guid}}
      state = %{context.state | character: character}
      assert Auction.sell(state, sale(context.npc, item.object.guid)) == state
      assert ItemStore.get(item.object.guid).item.owner == state.guid

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgAuctionCommandResult{action: :started, error: :inventory}}}
    end
  end

  describe "recover/1" do
    test "applies an unprojected receipt once and preserves later owner changes", context do
      character = context.state.character
      changes = %ChangeSet{player: %{character.player | coinage: 700}}

      receipt = %Receipt{
        id: make_ref(),
        guid: character.object.guid,
        changes: changes,
        old_counts: %{},
        outgoing: [],
        action: :bid_placed,
        auction: nil
      }

      AuctionStore.commit(%Change{book: AuctionStore.book()}, receipt)
      recovered = Auction.recover(character)
      assert recovered.player.coinage == 700
      assert recovered.internal.last_auction_id == receipt.id
      assert CharacterStore.get(character.id) == recovered

      updated = %{recovered | player: %{recovered.player | coinage: 725}}
      assert Auction.recover(updated) == updated
      state = Auction.finish_recovery(%{context.state | character: updated})
      assert state.character.player.coinage == 725
      assert AuctionStore.pending(state.guid) == nil
    end
  end

  defp auctioneer(_context) do
    houses = for id <- [1, 7], do: {id, AuctionHouse.get(id)}

    :ets.insert(AuctionHouse, [
      {1, %House{id: 1, market: :alliance, deposit_percent: 5, cut_percent: 5}},
      {7, %House{id: 7, market: :neutral, deposit_percent: 25, cut_percent: 15}}
    ])

    seller = character()
    buyer = character()
    {:ok, _owner} = Entity.register(seller.object.guid)
    {:ok, _owner} = Entity.register(buyer.object.guid)
    npc = Guid.from_low_guid(:mob, 8661, seller.id)
    Metadata.put(npc, %{npc_flags: 0x1000, alive?: true, faction_template: %FactionTemplate{id: 11}})
    SpatialHash.update(:mobs, npc, WorldRef.open(0), 2.0, 0.0, 0.0)

    for character <- [seller, buyer] do
      SpatialHash.update(:players, character.object.guid, WorldRef.open(0), 0.0, 0.0, 0.0)
    end

    on_exit(fn ->
      Metadata.delete(npc)
      SpatialHash.remove(:mobs, npc)

      for character <- [seller, buyer] do
        SpatialHash.remove(:players, character.object.guid)
        Metadata.delete(character.object.guid)
        :ets.delete(CharacterStore, character.id)
        :ets.delete(ItemStore, {:auction, :receipt, character.object.guid})
      end

      book = AuctionStore.book()
      auctions = Map.reject(book.auctions, fn {_id, auction} -> auction.owner == seller.object.guid end)
      AuctionStore.commit(%Change{book: %{book | auctions: auctions}})

      Enum.each(houses, &restore_house/1)
    end)

    %{
      npc: npc,
      state: %State{ready: true, guid: seller.object.guid, character: seller},
      buyer: %State{ready: true, guid: buyer.object.guid, character: buyer}
    }
  end

  defp restore_house({id, nil}), do: :ets.delete(AuctionHouse, id)
  defp restore_house({id, house}), do: :ets.insert(AuctionHouse, {id, house})

  defp character do
    id = System.unique_integer([:positive, :monotonic])

    %Character{
      id: id,
      account_id: id,
      object: %Object{guid: Guid.from_low_guid(:player, id)},
      unit: %Unit{race: 1, class: 1, level: 60, health: 100},
      player: %Player{coinage: 1_000},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0)}
    }
  end

  defp sale(npc, item_guid) do
    %Message.CmsgAuctionSellItem{
      auctioneer: npc,
      item_guid: item_guid,
      start_bid: 100,
      buyout: 200,
      duration_minutes: 120
    }
  end
end
