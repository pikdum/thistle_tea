defmodule ThistleTea.Game.Network.Message.SmsgLootRemoved do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_LOOT_REMOVED

  defstruct [:slot]

  @impl ServerMessage
  def to_binary(%__MODULE__{slot: slot}) do
    <<slot>>
  end
end
