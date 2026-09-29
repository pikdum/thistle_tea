defmodule ThistleTea.Game.Network.Message.CmsgNpcTextQuery do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_NPC_TEXT_QUERY

  alias ThistleTea.Game.Network.Message

  defstruct [:text_id, :guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<text_id::little-size(32), guid::little-size(64)>> = payload

    %__MODULE__{
      text_id: text_id,
      guid: guid
    }
  end
end
