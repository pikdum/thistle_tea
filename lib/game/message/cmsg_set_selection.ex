defmodule ThistleTea.Game.Message.CmsgSetSelection do
  use ThistleTea.Game.ClientMessage, :CMSG_SET_SELECTION

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, state) do
    Map.put(state, :target, guid)
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end
end
