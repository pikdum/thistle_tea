defmodule ThistleTea.Game.Network.Message.CmsgDuelAccepted do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_DUEL_ACCEPTED

  defstruct [:player_guid]

  @impl ClientMessage
  def from_binary(<<player_guid::little-size(64)>>) do
    %__MODULE__{player_guid: player_guid}
  end
end
