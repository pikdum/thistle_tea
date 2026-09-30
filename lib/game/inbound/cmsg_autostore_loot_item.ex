defmodule ThistleTea.Game.Inbound.CmsgAutostoreLootItem do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_AUTOSTORE_LOOT_ITEM

  alias ThistleTea.Game.World.Entity.Player.Looting

  defstruct [:slot]

  @impl ClientMessage
  def from_binary(<<slot>>), do: %__MODULE__{slot: slot}

  @impl ClientMessage
  def handle(%__MODULE__{slot: slot}, state), do: Looting.take_item(state, slot)
end
