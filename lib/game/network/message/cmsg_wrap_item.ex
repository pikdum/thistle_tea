defmodule ThistleTea.Game.Network.Message.CmsgWrapItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_WRAP_ITEM

  alias ThistleTea.Game.Player.Gifts

  defstruct [:gift_bag, :gift_slot, :item_bag, :item_slot]

  @impl ClientMessage
  def from_binary(<<gift_bag, gift_slot, item_bag, item_slot>>) do
    %__MODULE__{gift_bag: gift_bag, gift_slot: gift_slot, item_bag: item_bag, item_slot: item_slot}
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state) do
    Gifts.wrap(state, {message.gift_bag, message.gift_slot}, {message.item_bag, message.item_slot})
  end
end
