defmodule ThistleTea.Game.Network.MovementControlTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Network.Session

  describe "prepare/2" do
    test "assigns one sequence across acknowledged movement changes" do
      state = %Session{guid: 1}

      {speed, state} =
        MovementControl.prepare(%Message.SmsgForceRunSpeedChange{guid: 1, speed: 8.75}, state)

      {unroot, state} = MovementControl.prepare(%Message.SmsgForceMoveUnroot{guid: 1}, state)
      {teleport, state} = MovementControl.prepare(%Message.MsgMoveTeleportAck{guid: 1}, state)

      assert speed.move_event == 0
      assert unroot.move_event == 1
      assert teleport.counter == 2
      assert state.movement_counter == 3

      assert state.pending_movement_acks == %{
               0 => {:run_speed, 8.75},
               1 => :unroot,
               2 => :teleport
             }
    end

    test "also advances counters for movement flags without implemented acknowledgements" do
      state = %Session{guid: 1, movement_counter: 7}

      {packet, state} = MovementControl.prepare(%Message.SmsgMoveWaterWalk{guid: 1}, state)

      assert packet.counter == 7
      assert state.movement_counter == 8
      assert state.pending_movement_acks == %{}
    end
  end

  describe "repop sequencing" do
    test "waits for earlier movement acknowledgements before teleporting" do
      state = %Session{guid: 1, pending_movement_acks: %{4 => :unroot}}
      state = MovementControl.defer_repop(state, {10.0, 20.0, 30.0, 1})
      token = state.pending_repop.token

      assert_receive {:"$gen_cast", {:finish_repop, ^token}}

      state = MovementControl.finish_repop(state, token)
      refute_receive {:"$gen_cast", {:start_teleport, _, _, _, _}}

      assert {:ok, state} = MovementControl.acknowledge(state, 1, 4, :unroot)
      state = MovementControl.maybe_finish_repop(state)

      assert state.pending_repop == nil
      assert_receive {:"$gen_cast", {:start_teleport, 10.0, 20.0, 30.0, 1}}
    end

    test "forces the teleport after the acknowledgement timeout" do
      state = %Session{guid: 1, pending_movement_acks: %{4 => :unroot}}
      state = MovementControl.defer_repop(state, {10.0, 20.0, 30.0, 1})
      token = state.pending_repop.token

      assert_receive {:"$gen_cast", {:finish_repop, ^token}}
      state = MovementControl.finish_repop(state, token, true)

      assert state.pending_repop == nil
      assert state.pending_movement_acks == %{}
      assert_receive {:"$gen_cast", {:start_teleport, 10.0, 20.0, 30.0, 1}}
    end
  end
end
