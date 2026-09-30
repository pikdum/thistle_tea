defmodule ThistleTea.Game.Inbound.CmsgAutoequipItemSlot do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_AUTOEQUIP_ITEM_SLOT

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Inventory

  defstruct [:item_guid, :destination_slot]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), slot>>) do
    %__MODULE__{item_guid: guid, destination_slot: slot}
  end

  @impl ClientMessage
  def handle(%__MODULE__{item_guid: guid, destination_slot: slot}, %{ready: true, character: %Character{}} = state) do
    Inventory.equip_item(state, guid, slot)
  end

  def handle(%__MODULE__{}, state), do: state
end
