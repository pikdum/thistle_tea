defmodule ThistleTea.Game.Network.Message.CmsgAuctionListOwnerItems do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUCTION_LIST_OWNER_ITEMS

  alias ThistleTea.Game.Player.Auction

  defstruct [:auctioneer, :offset]
  @impl ClientMessage
  def from_binary(<<auctioneer::little-size(64), offset::little-size(32)>>) do
    %__MODULE__{auctioneer: auctioneer, offset: offset}
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Auction.owned(state, message)
end
