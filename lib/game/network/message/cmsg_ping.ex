defmodule ThistleTea.Game.Network.Message.CmsgPing do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PING

  defstruct [:sequence_id, :latency]

  @impl ClientMessage
  def from_binary(payload) do
    <<sequence_id::little-size(32), latency::little-size(32)>> = payload

    %__MODULE__{
      sequence_id: sequence_id,
      latency: latency
    }
  end
end
