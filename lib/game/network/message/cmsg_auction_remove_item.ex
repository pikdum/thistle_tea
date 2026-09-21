defmodule ThistleTea.Game.Network.Message.CmsgAuctionRemoveItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUCTION_REMOVE_ITEM

  alias ThistleTea.Game.Player.Auction

  defstruct [:auctioneer, :auction_id]
  @impl ClientMessage
  def from_binary(<<auctioneer::little-size(64), auction_id::little-size(32)>>) do
    %__MODULE__{auctioneer: auctioneer, auction_id: auction_id}
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Auction.cancel(state, message)
end
