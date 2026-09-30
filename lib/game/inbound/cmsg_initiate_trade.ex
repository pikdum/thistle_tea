defmodule ThistleTea.Game.Inbound.CmsgInitiateTrade do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_INITIATE_TRADE

  alias ThistleTea.Game.World.Entity.Player.Trade

  defstruct [:player_guid]

  @impl ClientMessage
  def from_binary(<<player_guid::little-size(64)>>), do: %__MODULE__{player_guid: player_guid}

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Trade.request(state, {:initiate, message.player_guid})
end
