defmodule ThistleTeaGame.Connection.Server do
  use ThousandIsland.Handler

  alias ThousandIsland.Socket
  alias ThistleTeaGame.Connection

  # TODO: how to get rid of these magic numbers?
  @smsg_auth_challenge 0x1EC

  @impl ThousandIsland.Handler
  def handle_connection(socket, %Connection{} = conn) do
    Socket.send(socket, <<6::big-size(16), @smsg_auth_challenge::little-size(16)>> <> conn.seed)
  end

  @impl ThousandIsland.Handler
  def handle_data(data, socket, %Connection{} = conn) do
    conn
    |> Connection.receive_data(data)
    |> Connection.enqueue_packets()
    |> Connection.handle_packets()
    |> Connection.process_effects(socket)
  end
end
