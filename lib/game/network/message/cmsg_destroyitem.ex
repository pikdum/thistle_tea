defmodule ThistleTea.Game.Network.Message.CmsgDestroyitem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_DESTROYITEM

  alias ThistleTea.Game.Player.Inventory

  defstruct [:bag, :slot, :count]

  @impl ClientMessage
  def handle(%__MODULE__{bag: bag, slot: slot}, %{ready: true, character: %Character{}} = state) do
    Inventory.destroy(state, {bag, slot})
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<bag, slot, count, _data1, _data2, _data3>> = payload

    %__MODULE__{
      bag: bag,
      slot: slot,
      count: count
    }
  end
end
