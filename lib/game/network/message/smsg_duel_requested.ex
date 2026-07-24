defmodule ThistleTea.Game.Network.Message.SmsgDuelRequested do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_DUEL_REQUESTED

  defstruct [:arbiter_guid, :initiator_guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{arbiter_guid: arbiter_guid, initiator_guid: initiator_guid}) do
    <<arbiter_guid::little-size(64), initiator_guid::little-size(64)>>
  end
end
