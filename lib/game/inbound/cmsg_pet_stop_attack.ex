defmodule ThistleTea.Game.Inbound.CmsgPetStopAttack do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_PET_STOP_ATTACK

  alias ThistleTea.Game.World.Entity.Player.PetActions

  defstruct [:pet_guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{pet_guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{pet_guid: guid}, state), do: PetActions.stop_attack(state, guid)
end
