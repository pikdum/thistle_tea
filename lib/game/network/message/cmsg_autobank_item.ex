defmodule ThistleTea.Game.Network.Message.CmsgAutobankItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_AUTOBANK_ITEM

  defstruct [:source_bag, :source_slot]

  @impl ClientMessage
  def from_binary(<<source_bag, source_slot>>) do
    %__MODULE__{source_bag: source_bag, source_slot: source_slot}
  end
end
