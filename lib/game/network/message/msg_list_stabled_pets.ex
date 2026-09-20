defmodule ThistleTea.Game.Network.Message.MsgListStabledPets do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_LIST_STABLED_PETS

  defstruct [:guid, slots: 0, pets: []]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, slots: slots, pets: pets}) do
    records =
      Enum.map(pets, fn pet ->
        <<pet.pet_number::little-size(32), pet.entry::little-size(32), pet.level::little-size(32), pet.name::binary, 0,
          pet.loyalty::little-size(32), pet.slot::little-size(8)>>
      end)

    IO.iodata_to_binary([<<guid::little-size(64), length(pets)::little-size(8), slots::little-size(8)>> | records])
  end
end
