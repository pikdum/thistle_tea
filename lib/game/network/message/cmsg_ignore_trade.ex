defmodule ThistleTea.Game.Network.Message.CmsgIgnoreTrade do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_IGNORE_TRADE

  alias ThistleTea.Game.Player.Trade

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Trade.request(state, {:cancel, :ignore_you})

  @impl ClientMessage
  def from_binary(<<>>), do: %__MODULE__{}
end
