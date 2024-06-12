defmodule ThistleTea.Game.Ping do
  defmacro __using__(_) do
    quote do
      @cmsg_ping 0x1DC
      @smsg_pong 0x1DD

      # handle encrypted ping
      @impl GenServer
      def handle_cast({:handle_packet, @cmsg_ping, _size, body}, {socket, state}) do
        <<sequence_id::little-size(32), latency::little-size(32)>> = body

        Logger.info(
          "[GameServer] Encrypted CMSG_PING: sequence_id: #{sequence_id}, latency: #{latency}"
        )

        send_packet(@smsg_pong, <<sequence_id::little-size(32)>>)
        {:noreply, {socket, Map.put(state, :latency, latency)}, socket.read_timeout}
      end

      # handle unecrypted ping
      @impl ThousandIsland.Handler
      def handle_data(
            <<size::big-size(16), @cmsg_ping::little-size(32), body::binary-size(size - 4),
              additional_data::binary>>,
            socket,
            state
          ) do
        if byte_size(additional_data) > 0, do: handle_data(additional_data, socket, state)
        <<sequence_id::little-size(32), latency::little-size(32)>> = body

        Logger.info(
          "[GameServer] Unencrypted CMSG_PING: sequence_id: #{sequence_id}, latency: #{latency}"
        )

        ThousandIsland.Socket.send(
          socket,
          <<6::big-size(16), @smsg_pong::little-size(16), sequence_id::little-size(32)>>
        )

        {:continue, Map.put(state, :latency, latency)}
      end
    end
  end
end
