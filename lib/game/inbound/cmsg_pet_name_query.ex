defmodule ThistleTea.Game.Inbound.CmsgPetNameQuery do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_PET_NAME_QUERY, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.Pets

  defstruct [:pet_number, :pet_guid]

  @impl ClientMessage
  def from_binary(<<pet_number::little-size(32), pet_guid::little-size(64)>>) do
    %__MODULE__{pet_number: pet_number, pet_guid: pet_guid}
  end

  @impl ClientMessage
  def handle(%__MODULE__{pet_number: number, pet_guid: guid}, state), do: Pets.query(state, guid, number)
end
