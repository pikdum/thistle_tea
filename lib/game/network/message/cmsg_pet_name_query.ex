defmodule ThistleTea.Game.Network.Message.CmsgPetNameQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PET_NAME_QUERY

  defstruct [:pet_number, :pet_guid]

  @impl ClientMessage
  def from_binary(<<pet_number::little-size(32), pet_guid::little-size(64)>>) do
    %__MODULE__{pet_number: pet_number, pet_guid: pet_guid}
  end
end
