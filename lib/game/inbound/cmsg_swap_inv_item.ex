defmodule ThistleTea.Game.Inbound.CmsgSwapInvItem do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_SWAP_INV_ITEM

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Inventory, as: InventoryCore
  alias ThistleTea.Game.World.Entity.Player.Inventory

  defstruct [:src_slot, :dst_slot]

  @impl ClientMessage
  def from_binary(payload) do
    <<src_slot, dst_slot>> = payload

    %__MODULE__{
      src_slot: src_slot,
      dst_slot: dst_slot
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{src_slot: src_slot, dst_slot: dst_slot}, %{ready: true, character: %Character{}} = state) do
    bag_0 = InventoryCore.bag_0()
    Inventory.swap(state, {bag_0, src_slot}, {bag_0, dst_slot})
  end

  def handle(%__MODULE__{}, state), do: state
end
