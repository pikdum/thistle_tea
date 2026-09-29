defmodule ThistleTea.Game.Network.Message.CmsgReadItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_READ_ITEM

  defstruct [:bag, :slot]

  @impl ClientMessage
  def from_binary(payload) do
    <<bag, slot>> = payload

    %__MODULE__{
      bag: bag,
      slot: slot
    }
  end
end
