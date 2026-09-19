defmodule ThistleTea.Game.Network.Message.CmsgRepairItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_REPAIR_ITEM

  alias ThistleTea.Game.Player.Durability

  defstruct [:vendor_guid, :item_guid]

  @impl ClientMessage
  def from_binary(<<vendor_guid::little-size(64), item_guid::little-size(64)>>) do
    %__MODULE__{vendor_guid: vendor_guid, item_guid: item_guid}
  end

  @impl ClientMessage
  def handle(%__MODULE__{vendor_guid: vendor_guid, item_guid: item_guid}, state) do
    Durability.repair(state, vendor_guid, item_guid)
  end
end
