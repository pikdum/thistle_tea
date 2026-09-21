defmodule ThistleTea.Game.Network.Message.MsgAuctionHelloClient do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_AUCTION_HELLO

  alias ThistleTea.Game.Player.Auction

  defstruct [:auctioneer]
  @impl ClientMessage
  def from_binary(<<auctioneer::little-size(64)>>) do
    %__MODULE__{auctioneer: auctioneer}
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Auction.hello(state, message.auctioneer)
end
