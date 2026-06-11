defmodule ThistleTea.Game.Network.Message.CmsgAutoequipItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUTOEQUIP_ITEM

  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.World.ItemStore

  defstruct [:src_bag, :src_slot]

  @impl ClientMessage
  def handle(%__MODULE__{src_bag: src_bag, src_slot: src_slot}, %{ready: true, character: %Character{} = c} = state) do
    Inventory.auto_equip(c.player, c.unit, state.guid, {src_bag, src_slot}, &ItemStore.get/1)
    |> then(&InventoryUpdate.apply(state, &1))
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<src_bag, src_slot>> = payload

    %__MODULE__{
      src_bag: src_bag,
      src_slot: src_slot
    }
  end
end
