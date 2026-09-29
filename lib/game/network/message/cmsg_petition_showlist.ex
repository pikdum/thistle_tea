defmodule ThistleTea.Game.Network.Message.CmsgPetitionShowlist do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PETITION_SHOWLIST

  defstruct [:npc_guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _rest::binary>>), do: %__MODULE__{npc_guid: guid}
end
