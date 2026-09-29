defmodule ThistleTea.Game.World.Entity.Player.Auction.ClientProjection do
  @moduledoc """
  Maps auction transitions to vanilla command results, listings, and notices.
  """

  alias ThistleTea.Game.Core.Auction
  alias ThistleTea.Game.Core.Auction.Notice
  alias ThistleTea.Game.Core.Auction.Receipt
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Outbound

  @inventory_errors [
    :dont_own_that_item,
    :item_locked,
    :cant_drop_soulbound,
    :cant_trade_equip_bags,
    :can_only_do_with_empty_bags,
    :not_in_combat
  ]

  def hello(guid, house), do: Outbound.send_packet(%Message.MsgAuctionHello{auctioneer: guid, house_id: house.id})

  def success(%Receipt{auction: auction, action: action}) do
    Outbound.send_packet(%Message.SmsgAuctionCommandResult{
      auction_id: auction.id,
      action: action,
      increment: Auction.increment(auction)
    })
  end

  def failure(id, action, {:error, {:higher_bid, auction}}) do
    Outbound.send_packet(%Message.SmsgAuctionCommandResult{
      auction_id: id,
      action: action,
      error: :higher_bid,
      bidder: auction.bidder,
      bid: auction.bid,
      increment: Auction.increment(auction)
    })
  end

  def failure(id, action, {:error, error}) when error in @inventory_errors do
    Outbound.send_packet(%Message.SmsgAuctionCommandResult{
      auction_id: id,
      action: action,
      error: :inventory,
      inventory_error: Inventory.error_code(error)
    })
  end

  def failure(id, action, {:error, error})
      when error in [:not_enough_money, :item_not_found, :higher_bid, :bid_increment, :bid_own] do
    Outbound.send_packet(%Message.SmsgAuctionCommandResult{auction_id: id, action: action, error: error})
  end

  def failure(id, action, _error) do
    Outbound.send_packet(%Message.SmsgAuctionCommandResult{auction_id: id, action: action, error: :database})
  end

  def list(kind, {auctions, total}, now) do
    module =
      case kind do
        :search -> Message.SmsgAuctionListResult
        :owned -> Message.SmsgAuctionOwnerListResult
        :bids -> Message.SmsgAuctionBidderListResult
      end

    Outbound.send_packet(struct!(module, auctions: auctions, total: total, now: now))
  end

  def notice(%Notice{auction: auction, kind: kind}) when kind in [:won, :outbid] do
    Outbound.send_packet(%Message.SmsgAuctionBidderNotification{
      house_id: auction.house.id,
      auction_id: auction.id,
      bidder: auction.bidder,
      bid: if(kind == :won, do: 0, else: auction.bid),
      increment: Auction.increment(auction),
      item_entry: auction.item.object.entry,
      random_property: auction.item.item.random_properties_id || 0
    })
  end

  def notice(%Notice{auction: auction, kind: kind}) when kind in [:sold, :bid_received, :expired] do
    Outbound.send_packet(%Message.SmsgAuctionOwnerNotification{
      auction_id: auction.id,
      bid: auction.bid,
      increment: Auction.increment(auction),
      bidder: if(kind == :bid_received, do: auction.bidder, else: 0),
      item_entry: auction.item.object.entry,
      random_property: auction.item.item.random_properties_id || 0
    })
  end

  def notice(%Notice{auction: auction, kind: :removed}) do
    Outbound.send_packet(%Message.SmsgAuctionRemovedNotification{
      auction_id: auction.id,
      item_entry: auction.item.object.entry,
      random_property: auction.item.item.random_properties_id || 0
    })
  end
end
