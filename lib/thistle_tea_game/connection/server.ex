defmodule ThistleTeaGame.Connection.Server do
  use ThousandIsland.Handler

  alias ThousandIsland.Socket
  alias ThistleTeaGame.Connection

  @smsg_auth_challenge ThistleTeaGame.Opcodes.get(:SMSG_AUTH_CHALLENGE)

  @impl ThousandIsland.Handler
  def handle_connection(socket, _) do
    conn = %Connection{}
    Socket.send(socket, <<6::big-size(16), @smsg_auth_challenge::little-size(16)>> <> conn.seed)
    {:continue, conn}
  end

  @impl ThousandIsland.Handler
  def handle_data(data, socket, %Connection{} = conn) do
    conn =
      conn
      |> Connection.receive_data(data)
      |> Connection.enqueue_packets()
      |> Connection.decode_packets()
      |> Connection.handle_packets()
      |> Connection.process_effects(socket)

    # |> dbg()

    {:continue, conn}
  end
end
