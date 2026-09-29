defmodule ThistleTea.Game.Network.Message.CmsgNameQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_NAME_QUERY

  alias ThistleTea.Game.Network.Message

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end
end
