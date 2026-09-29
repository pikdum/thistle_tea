defmodule ThistleTea.Game.Network.Message.CmsgUnacceptTrade do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_UNACCEPT_TRADE

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
