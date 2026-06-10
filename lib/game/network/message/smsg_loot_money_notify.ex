defmodule ThistleTea.Game.Network.Message.SmsgLootMoneyNotify do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_LOOT_MONEY_NOTIFY

  defstruct [:money]

  @impl ServerMessage
  def to_binary(%__MODULE__{money: money}) do
    <<money::little-size(32)>>
  end
end
