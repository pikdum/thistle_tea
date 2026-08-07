defmodule ThistleTea.Game.Network.Message.CmsgBuyItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BUY_ITEM

  alias ThistleTea.Game.Player.Vendor

  defstruct [:vendor_guid, :item_id, :count]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state) do
    Vendor.buy(state, message.vendor_guid, message.item_id, message.count)
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<vendor_guid::little-size(64), item_id::little-size(32), count, _unk>> = payload

    %__MODULE__{
      vendor_guid: vendor_guid,
      item_id: item_id,
      count: count
    }
  end
end
