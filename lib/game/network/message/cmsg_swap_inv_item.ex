defmodule ThistleTea.Game.Network.Message.CmsgSwapInvItem do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SWAP_INV_ITEM

  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.World.ItemStore

  defstruct [:src_slot, :dst_slot]

  @impl ClientMessage
  def handle(%__MODULE__{src_slot: src_slot, dst_slot: dst_slot}, %{ready: true, character: %Character{} = c} = state) do
    Inventory.swap(c.player, c.unit, src_slot, dst_slot, &ItemStore.get/1)
    |> then(&InventoryUpdate.apply(state, &1))
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<src_slot, dst_slot>> = payload

    %__MODULE__{
      src_slot: src_slot,
      dst_slot: dst_slot
    }
  end
end
