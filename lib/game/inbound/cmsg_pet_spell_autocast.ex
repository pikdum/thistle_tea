defmodule ThistleTea.Game.Inbound.CmsgPetSpellAutocast do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_PET_SPELL_AUTOCAST

  alias ThistleTea.Game.World.Entity.Player.PetActions

  defstruct [:pet_guid, :spell_id, :enabled?]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), id::little-size(32), enabled::8>>) do
    %__MODULE__{pet_guid: guid, spell_id: id, enabled?: enabled != 0}
  end

  @impl ClientMessage
  def handle(%__MODULE__{pet_guid: guid, spell_id: id, enabled?: enabled?}, state) do
    PetActions.controls(state, guid, {:autocast, id, enabled?})
  end
end
