defmodule ThistleTea.Game.Logout do
  defmacro __using__(_) do
    quote do
      @cmsg_logout_request 0x04B
      @smsg_logout_response 0x04C

      @cmsg_logout_cancel 0x04E
      @smsg_logout_cancel_ack 0x04F

      @smsg_logout_complete 0x04D
      @smsg_destroy_object 0x0AA

      @impl GenServer
      def handle_cast({:handle_packet, @cmsg_logout_request, _size, _body}, {socket, state}) do
        Logger.info("[GameServer] CMSG_LOGOUT_REQUEST")
        send_packet(@smsg_logout_response, <<0::little-size(32)>>)
        logout_timer = Process.send_after(self(), :send_logout_complete, 1_000)
        {:noreply, {socket, Map.put(state, :logout_timer, logout_timer)}}
      end

      @impl GenServer
      def handle_cast({:handle_packet, @cmsg_logout_cancel, _size, _body}, {socket, state}) do
        Logger.info("[GameServer] CMSG_LOGOUT_CANCEL")

        state =
          case Map.get(state, :logout_timer, nil) do
            nil ->
              state

            timer ->
              Process.cancel_timer(timer)
              Map.delete(state, :logout_timer)
          end

        send_packet(@smsg_logout_cancel_ack, <<>>)
        {:noreply, {socket, state}}
      end

      @impl GenServer
      def handle_info(:send_logout_complete, {socket, state}) do
        send_packet(@smsg_logout_complete, <<>>)
        # trigger :broadcast_logout
        GenServer.cast(self(), :broadcast_logout)
        {:noreply, {socket, state}}
      end

      @impl GenServer
      def handle_cast(:broadcast_logout, {socket, state}) do
        Registry.unregister(ThistleTea.PubSub, "test")

        if Map.get(state, :guid) do
          Registry.dispatch(ThistleTea.PubSub, "test", fn entries ->
            for {pid, _} <- entries do
              send(pid, {:send_packet, @smsg_destroy_object, <<state.guid::little-size(64)>>})
            end
          end)
        end

        {:noreply, {socket, state}}
      end
    end
  end
end
