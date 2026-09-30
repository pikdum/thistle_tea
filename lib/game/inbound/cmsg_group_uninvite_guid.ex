defmodule ThistleTea.Game.Inbound.CmsgGroupUninviteGuid do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GROUP_UNINVITE_GUID

  alias ThistleTea.Game.World.Entity.Player.Groups

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload
    %__MODULE__{guid: guid}
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Groups.uninvite_guid(state, guid)
end
