defmodule ThistleTea.Game.Network.Message.CmsgBeginTrade do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BEGIN_TRADE

  alias ThistleTea.Game.Player.Trade

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Trade.request(state, :open)

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
