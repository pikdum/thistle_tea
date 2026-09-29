defmodule ThistleTea.Game.Network.Message.CmsgCreatureQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CREATURE_QUERY

  alias ThistleTea.Game.Network.Message

  defstruct [:entry, :guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<entry::little-size(32), guid::little-size(64)>> = payload

    %__MODULE__{
      entry: entry,
      guid: guid
    }
  end
end
