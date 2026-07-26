defmodule ThistleTea.Game.Network.Server do
  @moduledoc """
  ThousandIsland transport for a world client connection.

  Authentication and character-selection messages run on the connection until
  login starts a player entity process. Once logged in, inbound messages are
  dispatched to that process and outbound packets arrive here already encoded.
  """
  use ThousandIsland.Handler
  use ThistleTea.Game.Network.Opcodes, [:SMSG_AUTH_CHALLENGE]

  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Network.Connection
  alias ThistleTea.Game.Network.ConnectionState
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Network.Send
  alias ThousandIsland.Socket

  require Logger

  @impl ThousandIsland.Handler
  def handle_data(data, _socket, %{conn: %Connection{} = conn} = state) do
    conn =
      conn
      |> Connection.receive_data(data)
      |> Connection.enqueue_packets()

    {:continue, handle_packets(%{state | conn: conn})}
  end

  def handle_packets(%{conn: %Connection{packet_queue: []}} = state), do: state

  def handle_packets(%{conn: %Connection{packet_queue: [packet | rest]}} = state) do
    message_name = Opcodes.get(packet.opcode)

    state =
      case Dispatch.implemented?(packet.opcode) do
        true ->
          :telemetry.span([:thistle_tea, :handle_packet], %{opcode: packet.opcode}, fn ->
            message = Dispatch.to_message(packet)
            state = dispatch_message(message, state)
            {state, %{opcode: packet.opcode}}
          end)

        false ->
          Logger.warning("Unimplemented: #{message_name}")
          state
      end

    state
    |> then(&%{&1 | conn: %{&1.conn | packet_queue: rest}})
    |> handle_packets()
  end

  @impl GenServer
  def handle_cast({:write_packet, %Packet{} = packet}, {socket, state}) do
    state = Send.send_packet(packet, {socket, state})
    {:noreply, {socket, state}, socket.read_timeout}
  end

  def handle_cast({:send_packet, packet}, {socket, state}) do
    state = Send.send_packet(packet, {socket, state})
    {:noreply, {socket, state}, socket.read_timeout}
  end

  def handle_cast({:send_packet, packet, _opts}, {socket, state}) do
    state = Send.send_packet(packet, {socket, state})
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(
        {:DOWN, monitor, :process, player_pid, {:shutdown, :logout}},
        {socket, %ConnectionState{player_pid: player_pid, player_monitor: monitor} = state}
      ) do
    state = ConnectionState.clear_player(state)
    state = Send.send_packet(%Message.SmsgLogoutComplete{}, {socket, state})
    {:noreply, {socket, state}, socket.read_timeout}
  end

  def handle_info(
        {:DOWN, monitor, :process, player_pid, reason},
        {_socket, %ConnectionState{player_pid: player_pid, player_monitor: monitor} = state}
      )
      when reason != :normal do
    Logger.error("player entity stopped: #{inspect(reason)}")
    {:close, ConnectionState.clear_player(state)}
  end

  def handle_info(
        {:DOWN, monitor, :process, player_pid, _reason},
        {socket, %ConnectionState{player_pid: player_pid, player_monitor: monitor} = state}
      ) do
    {:noreply, {socket, ConnectionState.clear_player(state)}, socket.read_timeout}
  end

  @impl ThousandIsland.Handler
  def handle_connection(socket, _) do
    conn = %Connection{}

    Socket.send(
      socket,
      <<6::big-size(16), @smsg_auth_challenge::little-size(16)>> <> conn.seed
    )

    {:continue, %ConnectionState{conn: conn}}
  end

  @impl ThousandIsland.Handler
  def handle_close(_socket, %ConnectionState{player_pid: player_pid}) when is_pid(player_pid) do
    Logger.info("CLIENT DISCONNECTED")
    PlayerServer.disconnect(player_pid)
  end

  def handle_close(_socket, _state) do
    Logger.info("CLIENT DISCONNECTED")
    :ok
  end

  defp dispatch_message(%Message.CmsgPing{} = message, %ConnectionState{} = state) do
    Message.handle(message, state)
  end

  defp dispatch_message(message, %ConnectionState{player_pid: player_pid} = state) when is_pid(player_pid) do
    :ok = PlayerServer.handle_message(player_pid, message)
    state
  end

  defp dispatch_message(message, state), do: Message.handle(message, state)
end
