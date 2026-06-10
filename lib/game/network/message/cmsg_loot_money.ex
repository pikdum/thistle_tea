defmodule ThistleTea.Game.Network.Message.CmsgLootMoney do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOOT_MONEY

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Network.InventoryUpdate

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, %{ready: true, character: %Character{} = c, loot_guid: loot_guid} = state)
      when is_integer(loot_guid) do
    case Entity.call(loot_guid, :loot_take_gold) do
      {:ok, gold} ->
        player = %{c.player | coinage: (c.player.coinage || 0) + gold}
        Network.send_packet(%Message.SmsgLootMoneyNotify{money: gold})
        Network.send_packet(%Message.SmsgLootClearMoney{})
        InventoryUpdate.apply(state, {:ok, player})

      _ ->
        state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
