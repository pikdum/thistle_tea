defmodule ThistleTea.Game.Inbound.CmsgGroupSetLeader do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GROUP_SET_LEADER

  alias ThistleTea.Game.World.Entity.Player.Groups

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload
    %__MODULE__{guid: guid}
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Groups.set_leader(state, guid)
end
