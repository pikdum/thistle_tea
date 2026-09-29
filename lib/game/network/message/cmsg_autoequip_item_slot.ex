defmodule ThistleTea.Game.Network.Message.CmsgAutoequipItemSlot do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUTOEQUIP_ITEM_SLOT

  alias ThistleTea.Game.World.Entity.Player.Inventory

  defstruct [:item_guid, :destination_slot]

  @impl ClientMessage
  def handle(%__MODULE__{item_guid: guid, destination_slot: slot}, %{ready: true, character: %Character{}} = state) do
    Inventory.equip_item(state, guid, slot)
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), slot>>) do
    %__MODULE__{item_guid: guid, destination_slot: slot}
  end
end
