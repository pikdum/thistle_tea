defmodule ThistleTea.Game.Auth do
  defmacro __using__(_) do
    quote do
      alias ThistleTea.SessionStorage
      alias ThistleTea.CryptoStorage
      import ThistleTea.Util, only: [parse_string: 1]

      @smsg_auth_challenge 0x1EC

      @cmsg_auth_session 0x1ED
      @smsg_auth_response 0x1EE

      @impl ThousandIsland.Handler
      def handle_connection(socket, _state) do
        Logger.info("[GameServer] SMSG_AUTH_CHALLENGE")
        seed = :crypto.strong_rand_bytes(4)
        Logger.info("[GameServer] pid: #{inspect(self())}")

        ThousandIsland.Socket.send(
          socket,
          <<6::big-size(16), @smsg_auth_challenge::little-size(16)>> <> seed
        )

        {:continue, %{seed: seed}}
      end

      @impl ThousandIsland.Handler
      def handle_data(
            <<size::big-size(16), @cmsg_auth_session::little-size(32),
              body::binary-size(size - 4)>>,
            _socket,
            state
          ) do
        <<_build::little-size(32), _server_id::little-size(32), rest::binary>> = body
        {:ok, username, rest} = parse_string(rest)

        <<client_seed::little-bytes-size(4), client_proof::little-bytes-size(20), _rest::binary>> =
          rest

        session = SessionStorage.get(username)

        server_proof =
          :crypto.hash(
            :sha,
            username <> <<0::little-size(32)>> <> client_seed <> state.seed <> session
          )

        if client_proof == server_proof do
          Logger.info("[GameServer] CMSG_AUTH_SESSION: success: #{username}")
          crypt = %{key: session, send_i: 0, send_j: 0, recv_i: 0, recv_j: 0}
          {:ok, crypto_pid} = CryptoStorage.start_link(crypt)
          send_packet(@smsg_auth_response, <<0x0C, 0::little-size(32), 0, 0::little-size(32)>>)
          {:continue, Map.merge(state, %{username: username, crypto_pid: crypto_pid})}
        else
          Logger.error("[GameServer] CMSG_AUTH_SESSION: error: #{username}")
          {:close, state}
        end
      end
    end
  end
end
