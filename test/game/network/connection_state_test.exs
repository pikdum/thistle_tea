defmodule ThistleTea.Game.Network.ConnectionStateTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Connection
  alias ThistleTea.Game.Network.ConnectionState

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
