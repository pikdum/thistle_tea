defmodule ThistleTea.Game.Network.Message.CmsgPetRename do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PET_RENAME

  alias ThistleTea.Game.Player.Pets

  defstruct [:pet_guid, :name]

  @impl ClientMessage
  def from_binary(<<pet_guid::little-size(64), rest::binary>>) do
    with {:ok, name, <<>>} <- BinaryUtils.parse_string(rest) do
      %__MODULE__{pet_guid: pet_guid, name: name}
    end
  end

  @impl ClientMessage
  def handle(%__MODULE__{pet_guid: guid, name: name}, state), do: Pets.rename(state, guid, name)
end
