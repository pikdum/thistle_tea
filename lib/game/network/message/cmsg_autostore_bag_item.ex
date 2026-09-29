defmodule ThistleTea.Game.Network.Message.CmsgAutostoreBagItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUTOSTORE_BAG_ITEM

  defstruct [:source_bag, :source_slot, :destination_bag]

  @impl ClientMessage
  def from_binary(<<source_bag, source_slot, destination_bag>>) do
    %__MODULE__{source_bag: source_bag, source_slot: source_slot, destination_bag: destination_bag}
  end
end
