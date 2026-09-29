defmodule ThistleTea.Game.Network.Message.CmsgSplitItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SPLIT_ITEM

  defstruct [:src_bag, :src_slot, :dst_bag, :dst_slot, :count]

  @impl ClientMessage
  def from_binary(payload) do
    <<src_bag, src_slot, dst_bag, dst_slot, count>> = payload

    %__MODULE__{
      src_bag: src_bag,
      src_slot: src_slot,
      dst_bag: dst_bag,
      dst_slot: dst_slot,
      count: count
    }
  end
end
