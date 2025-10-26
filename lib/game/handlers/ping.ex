defmodule ThistleTea.Game.Ping do
  use ThistleTea.Opcodes, [:CMSG_PING, :SMSG_PONG]

  alias ThistleTea.Game.Message
  alias ThistleTea.Util

  require Logger

  def handle_packet(@cmsg_ping, body, state) do
    <<sequence_id::little-size(32), latency::little-size(32)>> = body

    Logger.info("CMSG_PING: #{latency}")

    Util.send_packet(%Message.SmsgPong{sequence_id: sequence_id})
    {:continue, Map.put(state, :latency, latency)}
  end
end
