defmodule ThistleTea.Game.Inbound.CmsgUnacceptTrade do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_UNACCEPT_TRADE

  alias ThistleTea.Game.World.Entity.Player.Trade

  defstruct []

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Trade.request(state, :unaccept)
end
