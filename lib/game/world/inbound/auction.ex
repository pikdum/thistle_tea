defmodule ThistleTea.Game.World.Inbound.Auction do
  @moduledoc "Handles decoded auction house client messages."

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Auction

  def messages do
    [
      Message.CmsgAuctionListBidderItems,
      Message.CmsgAuctionListItems,
      Message.CmsgAuctionListOwnerItems,
      Message.CmsgAuctionPlaceBid,
      Message.CmsgAuctionRemoveItem,
      Message.CmsgAuctionSellItem,
      Message.MsgAuctionHelloClient
    ]
  end

  def handle(%Message.CmsgAuctionListBidderItems{} = message, state), do: Auction.bids(state, message)

  def handle(%Message.CmsgAuctionListItems{} = message, state), do: Auction.search(state, message)

  def handle(%Message.CmsgAuctionListOwnerItems{} = message, state), do: Auction.owned(state, message)

  def handle(%Message.CmsgAuctionPlaceBid{} = message, state), do: Auction.bid(state, message)

  def handle(%Message.CmsgAuctionRemoveItem{} = message, state), do: Auction.cancel(state, message)

  def handle(%Message.CmsgAuctionSellItem{} = message, state), do: Auction.sell(state, message)

  def handle(%Message.MsgAuctionHelloClient{} = message, state), do: Auction.hello(state, message.auctioneer)
end
