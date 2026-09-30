defmodule ThistleTea.Game.Inbound.CmsgRequestPartyMemberStats do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_REQUEST_PARTY_MEMBER_STATS

  alias ThistleTea.Game.World.Entity.Player.Groups

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload
    %__MODULE__{guid: guid}
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Groups.request_member_stats(state, guid)
end
