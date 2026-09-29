defmodule ThistleTea.Game.Network.Message.CmsgLootMoney do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOOT_MONEY

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
