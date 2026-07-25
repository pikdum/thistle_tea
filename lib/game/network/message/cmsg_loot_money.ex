defmodule ThistleTea.Game.Network.Message.CmsgLootMoney do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOOT_MONEY

  alias ThistleTea.Game.Player.Looting

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Looting.take_money(state)

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}
end
