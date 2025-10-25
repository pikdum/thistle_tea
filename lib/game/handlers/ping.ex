defmodule ThistleTea.Game.Ping do
  use ThistleTea.Opcodes, [:CMSG_PING, :SMSG_PONG]

  import ThistleTea.Util, only: [send_packet: 2]

  require Logger

  def handle_packet(@cmsg_ping, body, state) do
    <<sequence_id::little-size(32), latency::little-size(32)>> = body

    Logger.info("CMSG_PING: #{latency}")

    send_packet(@smsg_pong, <<sequence_id::little-size(32)>>)
    {:continue, Map.put(state, :latency, latency)}
  end
end
