defmodule ThistleTea.Game.Network.Message.CmsgPetCastSpell do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PET_CAST_SPELL

  alias ThistleTea.Game.Player.PetActions

  defstruct [:pet_guid, :spell_id, :spell_cast_targets]

  @impl ClientMessage
  def from_binary(<<pet_guid::little-size(64), spell_id::little-size(32), targets::binary>>) do
    %__MODULE__{pet_guid: pet_guid, spell_id: spell_id, spell_cast_targets: targets}
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: PetActions.cast(state, message)
end
