defmodule ThistleTea.Game.Network.Message.CmsgAutoequipItemSlot do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUTOEQUIP_ITEM_SLOT

  defstruct [:item_guid, :destination_slot]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), slot>>) do
    %__MODULE__{item_guid: guid, destination_slot: slot}
  end
end
