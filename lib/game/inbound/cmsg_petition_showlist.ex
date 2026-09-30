defmodule ThistleTea.Game.Inbound.CmsgPetitionShowlist do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_PETITION_SHOWLIST

  alias ThistleTea.Game.World.Entity.Player.Petitions

  defstruct [:npc_guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _rest::binary>>), do: %__MODULE__{npc_guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{npc_guid: guid}, state), do: Petitions.show_list(state, guid)
end
