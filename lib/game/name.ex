defmodule ThistleTea.Game.Name do
  defmacro __using__(_) do
    quote do
      @cmsg_name_query 0x050
      @smsg_name_query_response 0x051

      @impl GenServer
      def handle_cast({:handle_packet, @cmsg_name_query, _size, body}, {socket, state}) do
        <<guid::little-size(64)>> = body
        [{^guid, character_name, realm_name, race, gender, class}] = :ets.lookup(:guid_name, guid)

        Logger.info("CMSG_NAME_QUERY", target_name: character_name)

        send_packet(
          @smsg_name_query_response,
          <<guid::little-size(64)>> <>
            character_name <> <<0>> <> realm_name <> <<0>> <> <<race, gender, class>>
        )

        {:noreply, {socket, state}, socket.read_timeout}
      end
    end
  end
end
