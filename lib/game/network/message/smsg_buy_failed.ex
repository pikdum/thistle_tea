defmodule ThistleTea.Game.Network.Message.SmsgBuyFailed do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_BUY_FAILED

  @errors %{
    cant_find_item: 0,
    item_already_sold: 1,
    not_enough_money: 2,
    seller_dont_like_you: 4,
    distance_too_far: 5,
    item_sold_out: 7,
    cant_carry_more: 8,
    rank_require: 11,
    reputation_require: 12
  }

  defstruct [:vendor_guid, :item_id, :error]

  @impl ServerMessage
  def to_binary(%__MODULE__{vendor_guid: vendor_guid, item_id: item_id, error: error}) do
    <<vendor_guid::little-size(64), item_id::little-size(32), Map.fetch!(@errors, error)>>
  end
end
