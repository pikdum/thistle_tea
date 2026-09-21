defmodule ThistleTea.Game.Network.Message.SmsgAuctionBidderNotification do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_AUCTION_BIDDER_NOTIFICATION

  defstruct house_id: 0, auction_id: 0, bidder: 0, bid: 0, increment: 0, item_entry: 0, random_property: 0
  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.house_id::little-size(32), message.auction_id::little-size(32), message.bidder::little-size(64),
      message.bid::little-size(32), message.increment::little-size(32), message.item_entry::little-size(32),
      message.random_property::little-size(32)>>
  end
end
