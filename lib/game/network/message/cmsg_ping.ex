defmodule ThistleTea.Game.Network.Message.CmsgPing do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PING

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Util

  require Logger

  defstruct [:sequence_id, :latency]

  @impl ClientMessage
  def handle(%__MODULE__{sequence_id: sequence_id, latency: latency}, state) do
    Logger.info("CMSG_PING: #{latency}")

    Util.send_packet(%Message.SmsgPong{sequence_id: sequence_id})
    Map.put(state, :latency, latency)
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<sequence_id::little-size(32), latency::little-size(32)>> = payload

    %__MODULE__{
      sequence_id: sequence_id,
      latency: latency
    }
  end
end
