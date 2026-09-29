defmodule ThistleTea.Game.Network.Message.CmsgSwapInvItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SWAP_INV_ITEM

  defstruct [:src_slot, :dst_slot]

  @impl ClientMessage
  def from_binary(payload) do
    <<src_slot, dst_slot>> = payload

    %__MODULE__{
      src_slot: src_slot,
      dst_slot: dst_slot
    }
  end
end
