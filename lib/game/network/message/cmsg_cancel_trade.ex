defmodule ThistleTea.Game.Network.Message.CmsgCancelTrade do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CANCEL_TRADE

  alias ThistleTea.Game.Player.Trade

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Trade.request(state, {:cancel, :trade_canceled})

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
