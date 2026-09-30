defmodule ThistleTea.Game.Inbound.CmsgLootMoney do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_LOOT_MONEY

  alias ThistleTea.Game.World.Entity.Player.Looting

  defstruct []

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Looting.take_money(state)
end
