defmodule ThistleTea.Game.Inbound.CmsgOpenItem do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_OPEN_ITEM

  alias ThistleTea.Game.World.Entity.Player.Containers

  defstruct [:bag, :slot]

  @impl ClientMessage
  def from_binary(<<bag, slot>>), do: %__MODULE__{bag: bag, slot: slot}

  @impl ClientMessage
  def handle(%__MODULE__{bag: bag, slot: slot}, %{ready: true} = state), do: Containers.open(state, {bag, slot})

  def handle(%__MODULE__{}, state), do: state
end
