defmodule ThistleTea.Game.Inbound.MsgPetitionRenameClient do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :MSG_PETITION_RENAME

  alias ThistleTea.Game.World.Entity.Player.Petitions

  defstruct [:item_guid, :name]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), rest::binary>>) do
    {:ok, name, _rest} = BinaryUtils.parse_string(rest)
    %__MODULE__{item_guid: guid, name: name}
  end

  @impl ClientMessage
  def handle(%__MODULE__{item_guid: guid, name: name}, state), do: Petitions.rename(state, guid, name)
end
