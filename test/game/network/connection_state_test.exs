defmodule ThistleTea.Game.Network.ConnectionStateTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Connection
  alias ThistleTea.Game.Network.ConnectionState

  describe "inspect/1" do
    test "redacts credentials and authentication buffers in nested connection state" do
      state = %ConnectionState{
        account: %ThistleTea.Account{
          id: 42,
          username: "TEST",
          password_hash: "secret_hash",
          password_salt: "secret_salt",
          password_verifier: "secret_verifier"
        },
        conn: %Connection{
          session_key: "secret_key",
          binary_stream: "secret_stream",
          packet_queue: ["secret_packet"]
        }
      }

      inspected = inspect(state, limit: :infinity)
      assert inspected =~ "TEST"
      assert inspected =~ "id: 42"
      refute inspected =~ "secret_"
    end
  end

  describe "attach_player/2" do
    test "monitors the player without adding gameplay state to the connection" do
      state = ConnectionState.attach_player(%ConnectionState{}, self())

      assert state.player_pid == self()
      assert is_reference(state.player_monitor)
      refute Map.has_key?(state, :character)
    end
  end

  describe "clear_player/1" do
    test "keeps authentication and protocol state" do
      connection = %Connection{}

      state =
        %ConnectionState{account: %{username: "test"}, conn: connection}
        |> ConnectionState.attach_player(self())
        |> ConnectionState.clear_player()

      assert state == %ConnectionState{account: %{username: "test"}, conn: connection}
    end
  end
end
