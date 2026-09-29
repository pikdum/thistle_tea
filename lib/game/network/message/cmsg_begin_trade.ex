defmodule ThistleTea.Game.Network.Message.CmsgBeginTrade do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BEGIN_TRADE

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
