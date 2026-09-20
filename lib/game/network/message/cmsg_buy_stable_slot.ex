defmodule ThistleTea.Game.Network.Message.CmsgBuyStableSlot do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BUY_STABLE_SLOT

  alias ThistleTea.Game.Player.PetStable

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: PetStable.buy(state, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
