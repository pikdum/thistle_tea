defmodule ThistleTea.Game.Network.Message.CmsgAcceptTrade do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ACCEPT_TRADE

  defstruct [:unknown]

  @impl ClientMessage
  def from_binary(<<unknown::little-size(32)>>), do: %__MODULE__{unknown: unknown}
end
