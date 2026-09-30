defmodule ThistleTea.Game.Inbound.CmsgSplitItem do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_SPLIT_ITEM

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Inventory

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

  @impl ClientMessage
  def handle(%__MODULE__{count: count} = message, %{ready: true, character: %Character{}} = state) when count > 0 do
    src_pos = {message.src_bag, message.src_slot}
    dst_pos = {message.dst_bag, message.dst_slot}
    Inventory.split(state, src_pos, dst_pos, count)
  end

  def handle(%__MODULE__{}, state), do: state
end
