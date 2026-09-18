defmodule ThistleTea.Game.Network.Message.CmsgAutostoreBagItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUTOSTORE_BAG_ITEM

  alias ThistleTea.Game.Player.Inventory

  defstruct [:source_bag, :source_slot, :destination_bag]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, %{ready: true, character: %Character{}} = state) do
    Inventory.auto_store_in_bag(state, {message.source_bag, message.source_slot}, message.destination_bag)
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(<<source_bag, source_slot, destination_bag>>) do
    %__MODULE__{source_bag: source_bag, source_slot: source_slot, destination_bag: destination_bag}
  end
end
