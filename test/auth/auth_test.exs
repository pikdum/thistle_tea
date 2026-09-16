defmodule ThistleTea.AuthTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Account
  alias ThistleTea.Auth
  alias ThousandIsland.Socket
  alias ThousandIsland.Telemetry

  defmodule TestTransport do
    @moduledoc false

    def send(pid, data) do
      Kernel.send(pid, {:socket_send, data})
      :ok
    end
  end

  setup [:connection]

  describe "handle_data/3" do
    test "unknown logins receive a failure instead of crashing", %{socket: socket, username: username} do
      assert {:close, _state} = Auth.handle_data(challenge(0, username), socket, %{})
      assert_receive {:socket_send, <<0, 0, 4>>}
    end

    test "fragmented valid logins still receive an SRP challenge", %{socket: socket, username: username} do
      {:ok, _account} = Account.register(username, "test")
      <<head::binary-size(5), tail::binary>> = challenge(0, username)
      assert {:continue, state} = Auth.handle_data(head, socket, %{})
      refute_received {:socket_send, _packet}
      assert {:continue, state} = Auth.handle_data(tail, socket, state)
      assert state.account.username == username
      assert_receive {:socket_send, <<0, 0, 0, _rest::binary>>}
    end

    test "unknown reconnects and accounts without sessions fail cleanly", %{socket: socket, username: username} do
      assert {:close, _state} = Auth.handle_data(challenge(2, username), socket, %{})
      assert_receive {:socket_send, <<2, 4>>}
      {:ok, _account} = Account.register(username, "test")
      assert {:close, _state} = Auth.handle_data(challenge(2, username), socket, %{})
      assert_receive {:socket_send, <<2, 4>>}
    end

    test "reconnect challenge retains the account and accepts its proof", %{socket: socket, username: username} do
      {:ok, _account} = Account.register(username, "test")
      session = :crypto.strong_rand_bytes(40)
      :ets.insert(:session, {username, session})
      assert {:continue, state} = Auth.handle_data(challenge(2, username), socket, %{})
      assert_receive {:socket_send, <<2, 0, challenge_data::binary-size(16), _checksum_salt::binary-size(16)>>}
      proof_data = :crypto.strong_rand_bytes(16)
      proof = :crypto.hash(:sha, username <> proof_data <> challenge_data <> session)
      packet = <<3, proof_data::binary, proof::binary, 0::160, 0>>
      assert {:continue, _state} = Auth.handle_data(packet, socket, state)
      assert_receive {:socket_send, <<3, 0>>}
    end
  end

  defp connection(_context) do
    username = "AUTH_TEST_#{System.unique_integer([:positive])}"

    on_exit(fn ->
      :ets.delete(Account, username)
      :ets.delete(:session, username)
    end)

    span = %Telemetry{
      span_name: :connection,
      telemetry_span_context: make_ref(),
      start_time: 0,
      start_metadata: %{},
      handler: Auth,
      span_metadata: %{}
    }

    socket = %Socket{
      socket: self(),
      transport_module: TestTransport,
      read_timeout: 0,
      silent_terminate_on_error: false,
      span: span
    }

    %{socket: socket, username: username}
  end

  defp challenge(opcode, username) do
    body =
      <<"WoW", 0, 1, 12, 1, 5875::little-size(16), "68x", 0, "niW", 0, "SUne", 0::32, 0::32, byte_size(username),
        username::binary>>

    <<opcode, 3, byte_size(body)::little-size(16), body::binary>>
  end
end
