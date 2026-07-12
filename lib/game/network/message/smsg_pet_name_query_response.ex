defmodule ThistleTea.Game.Network.Message.SmsgPetNameQueryResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PET_NAME_QUERY_RESPONSE

  defstruct [:pet_number, :name, :timestamp]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.pet_number::little-size(32)>> <>
      (message.name || "") <>
      <<0>> <>
      <<message.timestamp || 0::little-size(32)>>
  end
end
