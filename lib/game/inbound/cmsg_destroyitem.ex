defmodule ThistleTea.Game.Inbound.CmsgDestroyitem do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_DESTROYITEM

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Inventory

  defstruct [:bag, :slot, :count]

  @impl ClientMessage
  def from_binary(payload) do
    <<bag, slot, count, _data1, _data2, _data3>> = payload

    %__MODULE__{
      bag: bag,
      slot: slot,
      count: count
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{bag: bag, slot: slot}, %{ready: true, character: %Character{}} = state) do
    Inventory.destroy(state, {bag, slot})
  end

  def handle(%__MODULE__{}, state), do: state
end
