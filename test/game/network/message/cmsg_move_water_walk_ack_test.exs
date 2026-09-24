defmodule ThistleTea.Game.Network.Message.CmsgMoveWaterWalkAckTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.CmsgMoveWaterWalkAck
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Network.Packet

  describe "from_binary/1" do
    test "dispatches the vanilla guid, counter, movement, and apply fields" do
      movement = <<0::size(224)>>
      payload = <<42::little-size(64), 7::little-size(32), movement::binary, 0x3F800000::little-size(32)>>

      assert %CmsgMoveWaterWalkAck{guid: 42, counter: 7, movement_payload: ^movement, apply: 0x3F800000} =
               Dispatch.to_message(Packet.build(payload, 0x2D0))
    end
  end

  describe "handle/2" do
    test "settles application and removal independently without replaying client movement" do
      {enabled, state} = MovementControl.prepare(%Message.SmsgMoveWaterWalk{guid: 42}, %State{guid: 42})
      {disabled, state} = MovementControl.prepare(%Message.SmsgMoveLandWalk{guid: 42}, state)

      state =
        CmsgMoveWaterWalkAck.handle(
          %CmsgMoveWaterWalkAck{guid: 42, counter: enabled.counter, movement_payload: <<>>, apply: 0x3F800000},
          state
        )

      assert state.pending_movement_acks == %{disabled.counter => {:water_walk, false}}

      state = CmsgMoveWaterWalkAck.handle(%CmsgMoveWaterWalkAck{guid: 42, counter: disabled.counter, apply: 0}, state)
      assert state.pending_movement_acks == %{}
    end

    test "rejects the wrong owner, counter, applied state, or movement kind" do
      state = %State{guid: 42, pending_movement_acks: %{7 => {:water_walk, true}, 8 => {:feather_fall, true}}}

      for {guid, counter, apply} <- [{41, 7, 1}, {42, 9, 1}, {42, 7, 0}, {42, 8, 1}] do
        message = %CmsgMoveWaterWalkAck{guid: guid, counter: counter, apply: apply}
        assert CmsgMoveWaterWalkAck.handle(message, state) == state
      end
    end

    test "the final acknowledgment releases a deferred spirit teleport" do
      token = make_ref()
      repop = %{token: token, position: {1.0, 2.0, 3.0}, map: 0}
      state = %State{guid: 42, pending_movement_acks: %{7 => {:water_walk, false}}, pending_repop: repop}
      state = CmsgMoveWaterWalkAck.handle(%CmsgMoveWaterWalkAck{guid: 42, counter: 7, apply: 0}, state)

      assert state.pending_repop == nil
      assert_received {:"$gen_cast", {:start_teleport, 1.0, 2.0, 3.0, 0}}
    end
  end
end
