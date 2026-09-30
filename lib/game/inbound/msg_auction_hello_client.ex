defmodule ThistleTea.Game.Inbound.MsgAuctionHelloClient do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :MSG_AUCTION_HELLO

  alias ThistleTea.Game.World.Entity.Player.Auction

  defstruct [:auctioneer]
  @impl ClientMessage
  def from_binary(<<auctioneer::little-size(64)>>) do
    %__MODULE__{auctioneer: auctioneer}
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Auction.hello(state, message.auctioneer)
end
