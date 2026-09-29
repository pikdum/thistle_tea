defmodule ThistleTea.Game.Network.Message.CmsgGameobjUse do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GAMEOBJ_USE

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), _rest::binary>> = payload

    %__MODULE__{
      guid: guid
    }
  end
end
