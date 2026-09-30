defmodule ThistleTea.Game.Inbound.CmsgLoot do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_LOOT

  alias ThistleTea.Game.World.Entity.Player.Looting

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state), do: Looting.open(state, guid)
end
