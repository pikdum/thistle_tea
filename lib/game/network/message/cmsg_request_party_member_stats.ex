defmodule ThistleTea.Game.Network.Message.CmsgRequestPartyMemberStats do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_REQUEST_PARTY_MEMBER_STATS

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload
    %__MODULE__{guid: guid}
  end
end
