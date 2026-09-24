defmodule ThistleTea.Game.Network.ServerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Connection
  alias ThistleTea.Game.Network.ConnectionState
  alias ThistleTea.Game.Network.Message.CmsgQuestgiverStatusQuery
  alias ThistleTea.Game.Network.Message.SmsgPong
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Network.Server
  alias ThousandIsland.Socket
  alias ThousandIsland.Telemetry

  defmodule TestTransport do
    @moduledoc false
    import Kernel, except: [send: 2]

    def send(pid, data) do
      Kernel.send(pid, {:socket_send, data})
      :ok
    end
  end

  describe "handle_connection/2" do
    test "creates protocol-only state and sends the authentication challenge" do
      socket = test_socket()

      assert {:continue, %ConnectionState{conn: %Connection{}} = state} =
               Server.handle_connection(socket, %{})

      refute Map.has_key?(state, :character)
      assert_receive {:socket_send, challenge}
      assert byte_size(challenge) == 8
    end
  end

  describe "handle_cast/2" do
    test "writes an encoded player packet without interpreting it" do
      socket = test_socket()
      state = %ConnectionState{conn: %Connection{session_key: <<0>>}}
      packet = %Packet{opcode: 0x123, payload: <<1, 2, 3>>}

      assert {:noreply, {^socket, %ConnectionState{}}, 0} =
               Server.handle_cast({:write_packet, packet}, {socket, state})

      assert_receive {:socket_send, data}
      assert is_binary(data)
    end
  end

  describe "handle_packets/1" do
    test "late queries during logout leave completion to the owner monitor" do
      player_pid =
        spawn(fn ->
          receive do
            {:"$gen_call", _from, {:client_message, %CmsgQuestgiverStatusQuery{}}} -> exit({:shutdown, :logout})
          end
        end)

      packet = %Packet{opcode: Opcodes.get(:CMSG_QUESTGIVER_STATUS_QUERY), payload: <<1::little-size(64)>>}
      state = %ConnectionState{account: %{id: 1}, conn: %Connection{session_key: <<0>>, packet_queue: [packet, packet]}}
      state = ConnectionState.attach_player(state, player_pid)
      monitor = state.player_monitor

      drained = Server.handle_packets(state)
      assert drained.player_pid == player_pid
      assert drained.conn.packet_queue == []
      refute_received {:socket_send, _packet}
      assert_receive {:DOWN, ^monitor, :process, ^player_pid, {:shutdown, :logout}} = down

      socket = test_socket()
      assert {:noreply, {^socket, detached}, 0} = Server.handle_info(down, {socket, drained})
      assert detached.player_pid == nil
      assert detached.player_monitor == nil
      assert detached.account == %{id: 1}
      assert_receive {:socket_send, _logout_complete}
      refute_received {:socket_send, _duplicate}
    end

    test "a query after owner exit does not consume the pending shutdown notification" do
      player_pid =
        spawn(fn ->
          receive do
            :logout -> exit({:shutdown, :logout})
          end
        end)

      packet = %Packet{opcode: Opcodes.get(:CMSG_QUESTGIVER_STATUS_QUERY), payload: <<1::little-size(64)>>}
      state = ConnectionState.attach_player(%ConnectionState{conn: %Connection{packet_queue: [packet]}}, player_pid)
      monitor = state.player_monitor
      send(player_pid, :logout)
      assert_receive {:DOWN, ^monitor, :process, ^player_pid, {:shutdown, :logout}} = down
      send(self(), down)

      assert %ConnectionState{player_pid: ^player_pid, player_monitor: ^monitor, conn: %Connection{packet_queue: []}} =
               Server.handle_packets(state)

      assert_receive ^down
    end

    test "unexpected failures still propagate while dispatching a message" do
      player_pid =
        spawn(fn ->
          receive do
            {:"$gen_call", _from, _message} -> exit(:boom)
          end
        end)

      packet = %Packet{opcode: Opcodes.get(:CMSG_QUESTGIVER_STATUS_QUERY), payload: <<1::little-size(64)>>}
      state = %ConnectionState{player_pid: player_pid, conn: %Connection{packet_queue: [packet]}}
      assert {:boom, {GenServer, :call, _args}} = catch_exit(Server.handle_packets(state))
    end

    test "handles ping on the connection before and after player attachment" do
      packet = %Packet{
        opcode: Opcodes.get(:CMSG_PING),
        payload: <<7::little-size(32), 42::little-size(32)>>
      }

      for player_pid <- [nil, self()] do
        state = %ConnectionState{
          player_pid: player_pid,
          conn: %Connection{packet_queue: [packet]}
        }

        assert %ConnectionState{latency: 42, conn: %Connection{packet_queue: []}} =
                 Server.handle_packets(state)

        assert_receive {:"$gen_cast", {:send_packet, %SmsgPong{sequence_id: 7}}}
      end
    end
  end

  describe "handle_info/2" do
    test "detaches the player before completing an explicit logout" do
      socket = test_socket()
      player_pid = self()
      monitor = make_ref()

      state = %ConnectionState{
        account: %{id: 1},
        player_pid: player_pid,
        player_monitor: monitor,
        conn: %Connection{session_key: <<0>>}
      }

      assert {:noreply, {^socket, detached}, 0} =
               Server.handle_info(
                 {:DOWN, monitor, :process, player_pid, {:shutdown, :logout}},
                 {socket, state}
               )

      assert detached.player_pid == nil
      assert detached.player_monitor == nil
      assert_receive {:socket_send, packet}
      assert is_binary(packet)
    end

    test "detaches a normally stopped player while keeping connection state" do
      socket = test_socket()
      player_pid = self()
      monitor = make_ref()

      state = %ConnectionState{
        account: %{id: 1},
        player_pid: player_pid,
        player_monitor: monitor
      }

      assert {:noreply, {^socket, detached}, 0} =
               Server.handle_info({:DOWN, monitor, :process, player_pid, :normal}, {socket, state})

      assert detached == %ConnectionState{account: %{id: 1}, latency: state.latency, conn: state.conn}
    end

    test "closes the connection when its player owner crashes" do
      player_pid = self()
      monitor = make_ref()

      state = %ConnectionState{
        account: %{id: 1},
        player_pid: player_pid,
        player_monitor: monitor
      }

      socket = test_socket()

      assert {:stop, {:shutdown, :local_closed}, {^socket, detached}} =
               Server.handle_info({:DOWN, monitor, :process, player_pid, :boom}, {socket, state})

      assert detached == %ConnectionState{account: %{id: 1}, latency: state.latency, conn: state.conn}
    end
  end

  defp test_socket do
    span = %Telemetry{
      span_name: :connection,
      telemetry_span_context: make_ref(),
      start_time: 0,
      start_metadata: %{},
      handler: Server,
      span_metadata: %{}
    }

    %Socket{
      socket: self(),
      transport_module: TestTransport,
      read_timeout: 0,
      silent_terminate_on_error: false,
      span: span
    }
  end
end
