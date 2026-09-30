defmodule ThistleTea.Game.Inbound.CmsgSwapItem do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_SWAP_ITEM

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Inventory

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

  @impl ClientMessage
  def handle(%__MODULE__{} = message, %{ready: true, character: %Character{}} = state) do
    Inventory.swap(state, {message.src_bag, message.src_slot}, {message.dst_bag, message.dst_slot})
  end

  def handle(%__MODULE__{}, state), do: state
end
