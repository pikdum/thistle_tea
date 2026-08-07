defmodule ThistleTea.Game.Network.Message.CmsgAutoequipItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUTOEQUIP_ITEM

  alias ThistleTea.Game.Player.Inventory

  defstruct [:src_bag, :src_slot]

  @impl ClientMessage
  def handle(%__MODULE__{src_bag: src_bag, src_slot: src_slot}, %{ready: true, character: %Character{}} = state) do
    Inventory.auto_equip(state, {src_bag, src_slot})
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<src_bag, src_slot>> = payload

    %__MODULE__{
      src_bag: src_bag,
      src_slot: src_slot
    }
  end
end
