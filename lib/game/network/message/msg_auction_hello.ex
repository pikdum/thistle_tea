defmodule ThistleTea.Game.Network.Message.MsgAuctionHello do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_AUCTION_HELLO

  defstruct auctioneer: 0, house_id: 0
  @impl ServerMessage
  def to_binary(%__MODULE__{} = message), do: <<message.auctioneer::little-size(64), message.house_id::little-size(32)>>
end
