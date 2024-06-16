defmodule ThistleTea.Game.Ping do
  import ThistleTea.Util, only: [send_packet: 2]

  require Logger

  @cmsg_ping 0x1DC
  @smsg_pong 0x1DD

  def handle_packet(@cmsg_ping, body, state) do
    <<sequence_id::little-size(32), latency::little-size(32)>> = body

    Logger.info("CMSG_PING: #{latency}")

    send_packet(@smsg_pong, <<sequence_id::little-size(32)>>)
    {:continue, Map.put(state, :latency, latency)}
  end
end
