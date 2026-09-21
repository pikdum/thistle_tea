defmodule ThistleTea.Game.Network.Message.CmsgAuctionPlaceBid do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUCTION_PLACE_BID

  alias ThistleTea.Game.Player.Auction

  defstruct [:auctioneer, :auction_id, :price]
  @impl ClientMessage
  def from_binary(<<auctioneer::little-size(64), auction_id::little-size(32), price::little-size(32)>>) do
    %__MODULE__{auctioneer: auctioneer, auction_id: auction_id, price: price}
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Auction.bid(state, message)
end
