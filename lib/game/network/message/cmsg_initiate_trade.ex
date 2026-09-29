defmodule ThistleTea.Game.Network.Message.CmsgInitiateTrade do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_INITIATE_TRADE

  defstruct [:player_guid]

  @impl ClientMessage
  def from_binary(<<player_guid::little-size(64)>>), do: %__MODULE__{player_guid: player_guid}
end
