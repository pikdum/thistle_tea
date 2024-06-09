defmodule ThistleTea.Game.Ping do
  defmacro __using__(_) do
    quote do
      @cmsg_ping 0x1DC
      @smsg_pong 0x1DD

      @impl GenServer
      def handle_cast({:handle_packet, @cmsg_ping, _size, body}, {socket, state}) do
        <<sequence_id::little-size(32), latency::little-size(32)>> = body
        Logger.info("[GameServer] CMSG_PING: sequence_id: #{sequence_id}, latency: #{latency}")
        send_packet(@smsg_pong, <<sequence_id::little-size(32)>>)
        {:noreply, {socket, Map.put(state, :latency, latency)}, socket.read_timeout}
      end
    end
  end
end
