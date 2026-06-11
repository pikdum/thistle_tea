defmodule ThistleTea.Game.Network.Message.CmsgDestroyitem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_DESTROYITEM

  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.World.ItemStore

  defstruct [:bag, :slot, :count]

  @impl ClientMessage
  def handle(%__MODULE__{bag: bag, slot: slot}, %{ready: true, character: %Character{} = c} = state) do
    case Inventory.destroy(c.player, {bag, slot}, &ItemStore.get/1) do
      {:ok, result, item} ->
        ItemStore.delete(item.object.guid)
        Network.send_packet(%Message.SmsgDestroyObject{guid: item.object.guid})
        InventoryUpdate.apply(state, {:ok, result})

      error ->
        InventoryUpdate.apply(state, error)
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<bag, slot, count, _data1, _data2, _data3>> = payload

    %__MODULE__{
      bag: bag,
      slot: slot,
      count: count
    }
  end
end
