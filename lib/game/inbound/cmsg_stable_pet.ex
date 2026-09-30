defmodule ThistleTea.Game.Inbound.CmsgStablePet do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_STABLE_PET

  alias ThistleTea.Game.World.Entity.Player.PetStable

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: PetStable.transfer(state, guid, :store)
end
