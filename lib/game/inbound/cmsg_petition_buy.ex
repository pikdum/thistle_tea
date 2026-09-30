defmodule ThistleTea.Game.Inbound.CmsgPetitionBuy do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_PETITION_BUY

  alias ThistleTea.Game.World.Entity.Player.Petitions

  defstruct [:npc_guid, :name]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), _unknown::little-size(32), _unknown_guid::little-size(64), rest::binary>>) do
    {:ok, name, _rest} = BinaryUtils.parse_string(rest)
    %__MODULE__{npc_guid: guid, name: name}
  end

  @impl ClientMessage
  def handle(%__MODULE__{npc_guid: guid, name: name}, state), do: Petitions.buy(state, guid, name)
end
