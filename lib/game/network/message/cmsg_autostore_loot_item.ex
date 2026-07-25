defmodule ThistleTea.Game.Network.Message.CmsgAutostoreLootItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUTOSTORE_LOOT_ITEM

  alias ThistleTea.Game.Player.Looting

  defstruct [:slot]

  @impl ClientMessage
  def handle(%__MODULE__{slot: slot}, state), do: Looting.take_item(state, slot)

  @impl ClientMessage
  def from_binary(<<slot>>), do: %__MODULE__{slot: slot}
end
