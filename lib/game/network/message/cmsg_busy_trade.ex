defmodule ThistleTea.Game.Network.Message.CmsgBusyTrade do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BUSY_TRADE

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
