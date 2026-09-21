defmodule ThistleTea.Game.Network.Message.CmsgAuctionSellItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUCTION_SELL_ITEM

  alias ThistleTea.Game.Player.Auction

  defstruct [:auctioneer, :item_guid, :start_bid, :buyout, :duration_minutes]
  @impl ClientMessage
  def from_binary(
        <<auctioneer::little-size(64), item_guid::little-size(64), start_bid::little-size(32), buyout::little-size(32),
          duration_minutes::little-size(32)>>
      ) do
    %__MODULE__{
      auctioneer: auctioneer,
      item_guid: item_guid,
      start_bid: start_bid,
      buyout: buyout,
      duration_minutes: duration_minutes
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Auction.sell(state, message)
end
