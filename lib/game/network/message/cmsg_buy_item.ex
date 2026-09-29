defmodule ThistleTea.Game.Network.Message.CmsgBuyItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BUY_ITEM

  defstruct [:vendor_guid, :item_id, :count]

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
