defmodule ThistleTea.Game.Network.Message.CmsgSwapInvItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SWAP_INV_ITEM

  alias ThistleTea.Game.Entity.Logic.Inventory, as: InventoryLogic
  alias ThistleTea.Game.Player.Inventory

  defstruct [:src_slot, :dst_slot]

  @impl ClientMessage
  def handle(%__MODULE__{src_slot: src_slot, dst_slot: dst_slot}, %{ready: true, character: %Character{}} = state) do
    bag_0 = InventoryLogic.bag_0()
    Inventory.swap(state, {bag_0, src_slot}, {bag_0, dst_slot})
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
