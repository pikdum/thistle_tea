defmodule ThistleTeaGame.Connection.Server do
  use ThousandIsland.Handler

  alias ThousandIsland.Socket
  alias ThistleTeaGame.Connection
  alias ThistleTeaGame.Connection.Crypto
  alias ThistleTeaGame.ClientPacket.Parse

  # TODO: how to get rid of these magic numbers?
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
end
