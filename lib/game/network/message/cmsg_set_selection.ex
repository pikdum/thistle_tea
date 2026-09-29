defmodule ThistleTea.Game.Network.Message.CmsgSetSelection do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_SELECTION

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end
end
