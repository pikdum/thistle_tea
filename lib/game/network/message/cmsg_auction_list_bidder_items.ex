defmodule ThistleTea.Game.Network.Message.CmsgAuctionListBidderItems do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUCTION_LIST_BIDDER_ITEMS

  alias ThistleTea.Game.Player.Auction

  defstruct [:auctioneer, :offset, :refresh_ids]
  @impl ClientMessage
  def from_binary(<<auctioneer::little-size(64), offset::little-size(32), count::little-size(32), rest::binary>>)
      when byte_size(rest) == count * 4 do
    %__MODULE__{auctioneer: auctioneer, offset: offset, refresh_ids: for(<<id::little-size(32) <- rest>>, do: id)}
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Auction.bids(state, message)
end
