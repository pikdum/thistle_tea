defmodule ThistleTea.Game.Network.Message.CmsgPetNameQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PET_NAME_QUERY

  alias ThistleTea.Game.World.Metadata

  defstruct [:pet_number, :pet_guid]

  @impl ClientMessage
  def handle(
        %__MODULE__{pet_number: pet_number, pet_guid: pet_guid},
        %{guid: owner_guid, character: %Character{unit: %Unit{summon: pet_guid}}} = state
      ) do
    case Metadata.query(pet_guid, [:name, :owner_guid]) do
      %{name: name, owner_guid: ^owner_guid} when is_binary(name) ->
        Network.send_packet(%Message.SmsgPetNameQueryResponse{
          pet_number: pet_number,
          name: name,
          timestamp: System.system_time(:second)
        })

      _ ->
        :ok
    end

    state
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(<<pet_number::little-size(32), pet_guid::little-size(64)>>) do
    %__MODULE__{pet_number: pet_number, pet_guid: pet_guid}
  end
end
