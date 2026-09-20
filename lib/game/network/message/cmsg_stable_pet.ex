defmodule ThistleTea.Game.Network.Message.CmsgStablePet do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_STABLE_PET

  alias ThistleTea.Game.Player.PetStable

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: PetStable.transfer(state, guid, :store)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
