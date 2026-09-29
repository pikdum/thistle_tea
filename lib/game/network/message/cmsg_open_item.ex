defmodule ThistleTea.Game.Network.Message.CmsgOpenItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_OPEN_ITEM

  defstruct [:bag, :slot]

  @impl ClientMessage
  def from_binary(<<bag, slot>>), do: %__MODULE__{bag: bag, slot: slot}
end
