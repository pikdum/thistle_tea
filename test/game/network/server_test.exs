defmodule ThistleTea.Game.Network.ServerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Connection
  alias ThistleTea.Game.Network.ConnectionState
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

      assert {:close, detached} =
               Server.handle_info({:DOWN, monitor, :process, player_pid, :boom}, {test_socket(), state})

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
