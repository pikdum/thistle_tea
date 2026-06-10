defmodule ThistleTea.Game.Network.Message.SmsgBuyItem do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_BUY_ITEM

  defstruct [:vendor_guid, :vendor_slot, new_count: 0xFFFFFFFF, count: 1]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.vendor_guid::little-size(64), message.vendor_slot::little-size(32), message.new_count::little-size(32),
      message.count::little-size(32)>>
  end
end
