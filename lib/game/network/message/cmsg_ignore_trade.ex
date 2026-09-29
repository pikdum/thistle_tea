defmodule ThistleTea.Game.Network.Message.CmsgIgnoreTrade do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_IGNORE_TRADE

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
