defmodule ThistleTea.Game.Network.Message.CmsgSwapItem do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SWAP_ITEM

  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.World.ItemStore

  defstruct [:dst_bag, :dst_slot, :src_bag, :src_slot]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, %{ready: true, character: %Character{} = c} = state) do
    if message.src_bag == Inventory.bag_0() and message.dst_bag == Inventory.bag_0() do
      Inventory.swap(c.player, c.unit, message.src_slot, message.dst_slot, &ItemStore.get/1)
      |> then(&InventoryUpdate.apply(state, &1))
    else
      InventoryUpdate.send_failure(:item_doesnt_go_to_slot, 0, 0)
      state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<dst_bag, dst_slot, src_bag, src_slot>> = payload

    %__MODULE__{
      dst_bag: dst_bag,
      dst_slot: dst_slot,
      src_bag: src_bag,
      src_slot: src_slot
    }
  end
end
