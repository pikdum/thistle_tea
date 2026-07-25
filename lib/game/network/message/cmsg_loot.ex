defmodule ThistleTea.Game.Network.Message.CmsgLoot do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOOT

  alias ThistleTea.Game.Player.Looting

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Looting.open(state, guid)

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
