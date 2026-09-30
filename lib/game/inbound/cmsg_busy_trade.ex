defmodule ThistleTea.Game.Inbound.CmsgBusyTrade do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_BUSY_TRADE

  alias ThistleTea.Game.World.Entity.Player.Trade

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Trade.request(state, {:cancel, :busy})
end
