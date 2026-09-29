defmodule ThistleTea.Game.Network.Message.CmsgDestroyitem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_DESTROYITEM

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
end
