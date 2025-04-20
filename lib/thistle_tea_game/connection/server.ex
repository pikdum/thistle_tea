defmodule ThistleTeaGame.Connection.Server do
  use ThousandIsland.Handler

  alias ThousandIsland.Socket
  alias ThistleTeaGame.Connection
  alias ThistleTeaGame.Connection.Crypto
  alias ThistleTeaGame.ClientPacket.Parse

  @smsg_auth_challenge 0x1EC
  @cmsg_auth_session 0x1ED

  @impl ThousandIsland.Handler
  def handle_connection(socket, %Connection{} = conn) do
    Socket.send(socket, <<6::big-size(16), @smsg_auth_challenge::little-size(16)>> <> conn.seed)
  end

  @impl ThousandIsland.Handler
  def handle_data(data, socket, %Connection{} = conn) do
    conn |> Connection.receive_data(data) |> Connection.enqueue_packets()
  end

  # TODO: instead of like this, just accumulate and then handle
  @impl ThousandIsland.Handler
  def handle_data(
        <<size::big-size(16), @cmsg_auth_session::little-size(32), body::binary-size(size - 4),
          additional_data::binary>>,
        socket,
        %Connection{} = conn
      ) do
    <<_build::little-size(32), _server_id::little-size(32), rest::binary>> = body
    {:ok, username, rest} = Parse.parse_string(rest)

    <<client_seed::little-bytes-size(4), client_proof::little-bytes-size(20), _rest::binary>> =
      rest

    [{^username, session_key}] = :ets.lookup(:session, username)

    case conn
         |> Map.put(:session_key, session_key)
         |> Crypto.verify_proof(username, client_seed, client_proof) do
      {:ok, conn} ->
        # TODO: send SMSG_AUTH_RESPONSE packet
        {:continue, conn}

      {:error, nil} ->
        {:close, conn}
    end
  end
end
