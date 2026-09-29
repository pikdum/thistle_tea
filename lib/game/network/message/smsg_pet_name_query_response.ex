defmodule ThistleTea.Game.Network.Message.SmsgPetNameQueryResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PET_NAME_QUERY_RESPONSE

  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Mob

  defstruct [:pet_number, :name, :timestamp]

  def for_pet(%Mob{internal: %{pet: %Pet{}, name: name}, unit: %{pet_number: number, pet_name_timestamp: timestamp}})
      when is_integer(number) and number > 0 and is_binary(name) do
    %__MODULE__{pet_number: number, name: name, timestamp: timestamp || 0}
  end

  def for_pet(_entity), do: nil

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.pet_number::little-size(32)>> <>
      (message.name || "") <>
      <<0>> <>
      <<message.timestamp || 0::little-size(32)>>
  end
end
