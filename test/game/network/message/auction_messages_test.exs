defmodule ThistleTea.Game.Network.Message.AuctionMessagesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Auction
  alias ThistleTea.Game.Entity.Data.Auction.House
  alias ThistleTea.Game.Entity.Data.Auction.Query
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet

  describe "client codecs and dispatch" do
    test "routes opening, selling, bidding, cancellation, and owner requests" do
      auctioneer = 0xF130_001122_334455
      item_guid = 0x4000_0000_0000_0011

      requests = [
        {:MSG_AUCTION_HELLO, <<auctioneer::little-size(64)>>, %Message.MsgAuctionHelloClient{auctioneer: auctioneer}},
        {:CMSG_AUCTION_SELL_ITEM,
         <<auctioneer::little-size(64), item_guid::little-size(64), 100::little-size(32), 200::little-size(32),
           120::little-size(32)>>,
         %Message.CmsgAuctionSellItem{
           auctioneer: auctioneer,
           item_guid: item_guid,
           start_bid: 100,
           buyout: 200,
           duration_minutes: 120
         }},
        {:CMSG_AUCTION_PLACE_BID, <<auctioneer::little-size(64), 8::little-size(32), 100::little-size(32)>>,
         %Message.CmsgAuctionPlaceBid{auctioneer: auctioneer, auction_id: 8, price: 100}},
        {:CMSG_AUCTION_REMOVE_ITEM, <<auctioneer::little-size(64), 8::little-size(32)>>,
         %Message.CmsgAuctionRemoveItem{auctioneer: auctioneer, auction_id: 8}},
        {:CMSG_AUCTION_LIST_OWNER_ITEMS, <<auctioneer::little-size(64), 50::little-size(32)>>,
         %Message.CmsgAuctionListOwnerItems{auctioneer: auctioneer, offset: 50}}
      ]

      for {opcode, payload, expected} <- requests do
        assert Dispatch.to_message(%Packet{opcode: Opcodes.get(opcode), payload: payload}) == expected
      end
    end

    test "decodes vanilla search fields without expansion-only sort bytes" do
      payload =
        <<123::little-size(64), 50::little-size(32), "Potion", 0, 10, 60, 0xFFFFFFFF::little-size(32),
          0::little-size(32), 1::little-size(32), 2::little-size(32), 1>>

      assert Dispatch.to_message(%Packet{opcode: Opcodes.get(:CMSG_AUCTION_LIST_ITEMS), payload: payload}) ==
               %Message.CmsgAuctionListItems{
                 auctioneer: 123,
                 query: %Query{
                   offset: 50,
                   name: "Potion",
                   level_min: 10,
                   level_max: 60,
                   class: 0,
                   subclass: 1,
                   quality: 2,
                   usable?: true
                 }
               }
    end

    test "decodes refresh ids and rejects truncated or extra bidder data" do
      payload = <<123::little-size(64), 0::little-size(32), 2::little-size(32), 7::little-size(32), 9::little-size(32)>>

      assert Dispatch.to_message(%Packet{opcode: Opcodes.get(:CMSG_AUCTION_LIST_BIDDER_ITEMS), payload: payload}) ==
               %Message.CmsgAuctionListBidderItems{auctioneer: 123, offset: 0, refresh_ids: [7, 9]}

      assert_raise FunctionClauseError, fn ->
        Message.CmsgAuctionListBidderItems.from_binary(binary_part(payload, 0, 20))
      end

      assert_raise FunctionClauseError, fn -> Message.CmsgAuctionListBidderItems.from_binary(payload <> <<0>>) end
    end
  end

  describe "server codecs" do
    test "opens a vanilla auction house without an enabled byte" do
      assert Message.MsgAuctionHello.to_binary(%Message.MsgAuctionHello{auctioneer: 123, house_id: 7}) ==
               <<123::little-size(64), 7::little-size(32)>>
    end

    test "encodes exact vanilla rows with enchantment, charges, suffix, and milliseconds" do
      auction = auction()

      expected =
        <<1::little-size(32), 9::little-size(32), 25::little-size(32), 1900::little-size(32), -5::little-size(32),
          1234::little-size(32), 3::little-size(32), -10::little-size(32), 12::little-size(64), 50::little-size(32),
          5::little-size(32), 200::little-size(32), 7_200_000::little-size(32), 13::little-size(64),
          100::little-size(32), 73::little-size(32)>>

      for module <- [
            Message.SmsgAuctionListResult,
            Message.SmsgAuctionOwnerListResult,
            Message.SmsgAuctionBidderListResult
          ] do
        message = struct!(module, auctions: [auction], total: 73, now: 1_000)
        assert module.to_binary(message) == expected
        assert byte_size(expected) == 72
      end
    end

    test "clamps expired rows and leaves an unbid minimum increment at zero" do
      auction = %{auction() | expires_at: 0, bid: 0, bidder: 0}

      binary =
        Message.SmsgAuctionListResult.to_binary(%Message.SmsgAuctionListResult{
          auctions: [auction],
          total: 1,
          now: 1_000
        })

      assert <<_prefix::binary-size(44), 0::little-size(32), 200::little-size(32), 0::little-size(32),
               0::little-size(64), 0::little-size(32), 1::little-size(32)>> = binary
    end

    test "encodes conditional command-result trailers" do
      assert result(%Message.SmsgAuctionCommandResult{auction_id: 9, action: :started}) ==
               <<9::little-size(32), 0::little-size(32), 0::little-size(32)>>

      assert result(%Message.SmsgAuctionCommandResult{auction_id: 9, action: :bid_placed, increment: 5}) ==
               <<9::little-size(32), 2::little-size(32), 0::little-size(32), 5::little-size(32)>>

      assert result(%Message.SmsgAuctionCommandResult{
               auction_id: 9,
               action: :removed,
               error: :inventory,
               inventory_error: 4
             }) ==
               <<9::little-size(32), 1::little-size(32), 1::little-size(32), 4::little-size(32)>>

      assert result(%Message.SmsgAuctionCommandResult{
               auction_id: 9,
               action: :bid_placed,
               error: :higher_bid,
               bidder: 13,
               bid: 100,
               increment: 5
             }) ==
               <<9::little-size(32), 2::little-size(32), 5::little-size(32), 13::little-size(64), 100::little-size(32),
                 5::little-size(32)>>
    end

    test "encodes bidder, owner, and removal notices" do
      assert Message.SmsgAuctionBidderNotification.to_binary(%Message.SmsgAuctionBidderNotification{
               house_id: 1,
               auction_id: 9,
               bidder: 13,
               bid: 100,
               increment: 5,
               item_entry: 25,
               random_property: -5
             }) ==
               <<1::little-size(32), 9::little-size(32), 13::little-size(64), 100::little-size(32), 5::little-size(32),
                 25::little-size(32), -5::little-size(32)>>

      assert Message.SmsgAuctionOwnerNotification.to_binary(%Message.SmsgAuctionOwnerNotification{
               auction_id: 9,
               bid: 100,
               increment: 5,
               bidder: 0,
               item_entry: 25,
               random_property: -5
             }) ==
               <<9::little-size(32), 100::little-size(32), 5::little-size(32), 0::little-size(64), 25::little-size(32),
                 -5::little-size(32)>>

      assert Message.SmsgAuctionRemovedNotification.to_binary(%Message.SmsgAuctionRemovedNotification{
               auction_id: 9,
               item_entry: 25,
               random_property: -5
             }) ==
               <<9::little-size(32), 25::little-size(32), -5::little-size(32)>>
    end
  end

  defp result(message), do: Message.SmsgAuctionCommandResult.to_binary(message)

  defp auction do
    item = Item.build(%ItemTemplate{entry: 25, spellcharges_1: -10}, 100, stack_count: 3)
    item = Item.put_permanent_enchantment(item, 1900)
    item = %{item | item: %{item.item | random_properties_id: -5, property_seed: 1234}}

    %Auction{
      id: 9,
      house: %House{id: 1, market: :alliance, deposit_percent: 5, cut_percent: 5},
      item: item,
      owner: 12,
      owner_account: 12,
      start_bid: 50,
      buyout: 200,
      deposit: 15,
      created_at: 1_000,
      expires_at: 7_201_000,
      bidder: 13,
      bid: 100
    }
  end
end
