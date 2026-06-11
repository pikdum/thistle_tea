defmodule ThistleTea.Game.Network.Message.SmsgSellItem do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SELL_ITEM

  @errors %{
    cant_find_item: 1,
    cant_sell_item: 2,
    cant_find_vendor: 3,
    you_dont_own_that_item: 4,
    only_empty_bag: 6
  }

  defstruct [:vendor_guid, :item_guid, :error]

  @impl ServerMessage
  def to_binary(%__MODULE__{vendor_guid: vendor_guid, item_guid: item_guid, error: error}) do
    <<vendor_guid::little-size(64), item_guid::little-size(64), Map.fetch!(@errors, error)>>
  end
end
