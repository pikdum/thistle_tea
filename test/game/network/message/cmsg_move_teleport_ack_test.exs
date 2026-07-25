defmodule ThistleTea.Game.Network.Message.CmsgMoveTeleportAckTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.CmsgMoveTeleportAck
  alias ThistleTea.Game.Network.Session

  describe "handle/2" do
    test "restores a suspended pet after the matching teleport acknowledgement" do
      state = %Session{guid: 1, pending_movement_acks: %{7 => :teleport}}

      state = CmsgMoveTeleportAck.handle(%CmsgMoveTeleportAck{guid: 1, counter: 7}, state)

      assert state.pending_movement_acks == %{}
      assert_receive :restore_active_pet
    end

    test "does not restore a pet for a stale teleport acknowledgement" do
      state = %Session{guid: 1, pending_movement_acks: %{7 => :teleport}}

      state = CmsgMoveTeleportAck.handle(%CmsgMoveTeleportAck{guid: 1, counter: 6}, state)

      assert state.pending_movement_acks == %{7 => :teleport}
      refute_receive :restore_active_pet
    end
  end
end
