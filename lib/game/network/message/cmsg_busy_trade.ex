defmodule ThistleTea.Game.Network.Message.CmsgBusyTrade do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BUSY_TRADE

  alias ThistleTea.Game.Player.Trade

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Trade.request(state, {:cancel, :busy})

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
