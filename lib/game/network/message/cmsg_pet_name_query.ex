defmodule ThistleTea.Game.Network.Message.CmsgPetNameQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PET_NAME_QUERY

  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.World.Metadata

  defstruct [:pet_number, :pet_guid]

  @impl ClientMessage
  def handle(
        %__MODULE__{pet_number: pet_number, pet_guid: pet_guid},
        %{guid: owner_guid, character: %Character{} = c} = state
      ) do
    if Companion.summon_guid(c) == pet_guid do
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
    end

    state
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(<<pet_number::little-size(32), pet_guid::little-size(64)>>) do
    %__MODULE__{pet_number: pet_number, pet_guid: pet_guid}
  end
end
