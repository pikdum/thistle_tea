defmodule ThistleTea.Game.Player.TravelTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message.CmsgMoveWorldportAck
  alias ThistleTea.Game.Player.Travel

  describe "worldport_ack/1" do
    test "ignores unsolicited and replayed worldport acknowledgements" do
      for state <- [%State{ready: false}, %State{ready: true}] do
        assert Travel.worldport_ack(state) == state
        assert CmsgMoveWorldportAck.handle(%CmsgMoveWorldportAck{}, state) == state
        refute_received _message
      end
    end
  end

  describe "teleport_ack/3" do
    test "completes combat relocation without pet restoration or arrival work" do
      state = %State{guid: 1, pending_movement_acks: %{1 => :combat_teleport}}
      assert %{pending_movement_acks: pending} = Travel.teleport_ack(state, 1, 1)
      assert pending == %{}
      refute_received _message
    end

    test "rejects stale and foreign acknowledgements" do
      state = %State{guid: 1, pending_movement_acks: %{1 => :teleport}}
      assert Travel.teleport_ack(state, 1, 0) == state
      assert Travel.teleport_ack(state, 2, 1) == state
      refute_received _message
    end
  end
end
