defmodule ThistleTea.Game.Network.Message.SmsgAuctionOwnerNotification do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_AUCTION_OWNER_NOTIFICATION

  defstruct auction_id: 0, bid: 0, increment: 0, bidder: 0, item_entry: 0, random_property: 0
  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.auction_id::little-size(32), message.bid::little-size(32), message.increment::little-size(32),
      message.bidder::little-size(64), message.item_entry::little-size(32), message.random_property::little-size(32)>>
  end
end
