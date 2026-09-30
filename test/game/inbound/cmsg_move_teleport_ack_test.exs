defmodule ThistleTea.Game.Inbound.CmsgMoveTeleportAckTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Inbound
  alias ThistleTea.Game.Inbound.CmsgMoveTeleportAck
  alias ThistleTea.Game.World.Entity.Player.State

  describe "handle/2" do
    test "restores a suspended pet after the matching teleport acknowledgement" do
      state = %State{guid: 1, pending_movement_acks: %{7 => :teleport}}

      state = Inbound.handle(%CmsgMoveTeleportAck{guid: 1, counter: 7}, state)

      assert state.pending_movement_acks == %{}
      assert_receive :restore_companion
    end

    test "does not restore a pet for a stale teleport acknowledgement" do
      state = %State{guid: 1, pending_movement_acks: %{7 => :teleport}}

      state = Inbound.handle(%CmsgMoveTeleportAck{guid: 1, counter: 6}, state)

      assert state.pending_movement_acks == %{7 => :teleport}
      refute_receive :restore_companion
    end
  end
end
