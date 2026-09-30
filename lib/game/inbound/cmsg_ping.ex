defmodule ThistleTea.Game.Inbound.CmsgPing do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_PING, while_possessed: true

  alias ThistleTea.Game.Network.ConnectionState
  alias ThistleTea.Game.World.Outbound

  require Logger

  defstruct [:sequence_id, :latency]

  @impl ClientMessage
  def from_binary(payload) do
    <<sequence_id::little-size(32), latency::little-size(32)>> = payload

    %__MODULE__{
      sequence_id: sequence_id,
      latency: latency
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{sequence_id: sequence_id, latency: latency}, %ConnectionState{} = state) do
    Logger.info("CMSG_PING: #{latency}")

    Outbound.send_packet(%Message.SmsgPong{sequence_id: sequence_id})
    %{state | latency: latency}
  end
end
