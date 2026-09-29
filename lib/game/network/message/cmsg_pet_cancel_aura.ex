defmodule ThistleTea.Game.Network.Message.CmsgPetCancelAura do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PET_CANCEL_AURA

  defstruct [:pet_guid, :spell_id]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), spell::little-size(32)>>), do: %__MODULE__{pet_guid: guid, spell_id: spell}
end
