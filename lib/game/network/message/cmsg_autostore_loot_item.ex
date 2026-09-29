defmodule ThistleTea.Game.Network.Message.CmsgAutostoreLootItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUTOSTORE_LOOT_ITEM

  defstruct [:slot]

  @impl ClientMessage
  def from_binary(<<slot>>), do: %__MODULE__{slot: slot}
end
