defmodule ThistleTea.Game.Network.Message.CmsgSwapItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SWAP_ITEM

  defstruct [:dst_bag, :dst_slot, :src_bag, :src_slot]

  @impl ClientMessage
  def from_binary(payload) do
    <<dst_bag, dst_slot, src_bag, src_slot>> = payload

    %__MODULE__{
      dst_bag: dst_bag,
      dst_slot: dst_slot,
      src_bag: src_bag,
      src_slot: src_slot
    }
  end
end
