defmodule ThistleTea.Game.Inbound.CmsgReadItem do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_READ_ITEM

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.UsableItems

  defstruct [:bag, :slot]

  @impl ClientMessage
  def from_binary(payload) do
    <<bag, slot>> = payload

    %__MODULE__{
      bag: bag,
      slot: slot
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{bag: bag, slot: slot}, %{ready: true, character: %Character{}} = state),
    do: UsableItems.read(state, {bag, slot})

  def handle(%__MODULE__{}, state), do: state
end
