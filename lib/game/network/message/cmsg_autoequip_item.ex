defmodule ThistleTea.Game.Network.Message.CmsgAutoequipItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUTOEQUIP_ITEM

  defstruct [:src_bag, :src_slot]

  @impl ClientMessage
  def from_binary(payload) do
    <<src_bag, src_slot>> = payload

    %__MODULE__{
      src_bag: src_bag,
      src_slot: src_slot
    }
  end
end
