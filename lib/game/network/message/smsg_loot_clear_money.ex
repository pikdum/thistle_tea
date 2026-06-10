defmodule ThistleTea.Game.Network.Message.SmsgLootClearMoney do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_LOOT_CLEAR_MONEY

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}) do
    <<>>
  end
end
