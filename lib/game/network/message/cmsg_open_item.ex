defmodule ThistleTea.Game.Network.Message.CmsgOpenItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_OPEN_ITEM

  alias ThistleTea.Game.Player.Containers

  defstruct [:bag, :slot]

  @impl ClientMessage
  def from_binary(<<bag, slot>>), do: %__MODULE__{bag: bag, slot: slot}

  @impl ClientMessage
  def handle(%__MODULE__{bag: bag, slot: slot}, %{ready: true} = state), do: Containers.open(state, {bag, slot})
  def handle(_message, state), do: state
end
