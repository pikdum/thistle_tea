defmodule ThistleTea.Game.Network.Message.CmsgUnacceptTrade do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_UNACCEPT_TRADE

  alias ThistleTea.Game.Player.Trade

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Trade.request(state, :unaccept)

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
