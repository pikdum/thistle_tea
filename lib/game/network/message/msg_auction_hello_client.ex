defmodule ThistleTea.Game.Network.Message.MsgAuctionHelloClient do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_AUCTION_HELLO

  defstruct [:auctioneer]
  @impl ClientMessage
  def from_binary(<<auctioneer::little-size(64)>>) do
    %__MODULE__{auctioneer: auctioneer}
  end
end
