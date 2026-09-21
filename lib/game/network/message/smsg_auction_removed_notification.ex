defmodule ThistleTea.Game.Network.Message.SmsgAuctionRemovedNotification do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_AUCTION_REMOVED_NOTIFICATION

  defstruct auction_id: 0, item_entry: 0, random_property: 0
  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.auction_id::little-size(32), message.item_entry::little-size(32),
      message.random_property::little-size(32)>>
  end
end
