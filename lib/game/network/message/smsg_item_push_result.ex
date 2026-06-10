defmodule ThistleTea.Game.Network.Message.SmsgItemPushResult do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ITEM_PUSH_RESULT

  defstruct [
    :player_guid,
    :item_id,
    :bag_slot,
    :item_slot,
    received: 0,
    created: 0,
    show_in_chat: 1,
    count: 1
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.player_guid::little-size(64), message.received::little-size(32), message.created::little-size(32),
      message.show_in_chat::little-size(32), message.bag_slot, message.item_slot::little-size(32),
      message.item_id::little-size(32), 0::little-size(32), 0::little-size(32), message.count::little-size(32)>>
  end
end
