defmodule ThistleTea.Game.Network.Message.SmsgAuctionBidderListResult do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_AUCTION_BIDDER_LIST_RESULT

  alias ThistleTea.Game.Network.Message.AuctionList

  defstruct auctions: [], total: 0, now: 0
  @impl ServerMessage
  def to_binary(%__MODULE__{} = message), do: AuctionList.to_binary(message.auctions, message.total, message.now)
end
