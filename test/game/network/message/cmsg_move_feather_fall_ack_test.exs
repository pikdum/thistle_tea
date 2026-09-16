defmodule ThistleTea.Game.Network.Message.CmsgMoveFeatherFallAckTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.CmsgMoveFeatherFallAck
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Network.Packet

  describe "from_binary/1" do
    test "dispatches a vanilla acknowledgment with its trailing apply flag" do
      movement = <<0::size(224)>>
      payload = <<42::little-size(64), 7::little-size(32), movement::binary, 1::little-size(32)>>

      assert %CmsgMoveFeatherFallAck{guid: 42, counter: 7, movement_payload: ^movement, apply: 1} =
               Dispatch.to_message(Packet.build(payload, 0x2CF))
    end
  end

  describe "handle/2" do
    test "settles both enabling and disabling Slow Fall" do
      {enabled, state} = MovementControl.prepare(%Message.SmsgMoveFeatherFall{guid: 42}, %State{guid: 42})
      {disabled, state} = MovementControl.prepare(%Message.SmsgMoveNormalFall{guid: 42}, state)

      state =
        CmsgMoveFeatherFallAck.handle(%CmsgMoveFeatherFallAck{guid: 42, counter: enabled.counter, apply: 1}, state)

      assert state.pending_movement_acks == %{disabled.counter => {:feather_fall, false}}

      state =
        CmsgMoveFeatherFallAck.handle(%CmsgMoveFeatherFallAck{guid: 42, counter: disabled.counter, apply: 0}, state)

      assert state.pending_movement_acks == %{}
    end

    test "rejects the wrong owner, counter, or applied state" do
      state = %State{guid: 42, pending_movement_acks: %{7 => {:feather_fall, true}}}

      for {guid, counter, apply} <- [{41, 7, 1}, {42, 8, 1}, {42, 7, 0}] do
        message = %CmsgMoveFeatherFallAck{guid: guid, counter: counter, apply: apply}
        assert CmsgMoveFeatherFallAck.handle(message, state) == state
      end
    end

    test "accepts the nonzero apply word sent by build 5875" do
      payload = <<42::little-size(64), 7::little-size(32), 0::size(224), 0x3F800000::little-size(32)>>
      message = CmsgMoveFeatherFallAck.from_binary(payload)
      state = %State{guid: 42, pending_movement_acks: %{7 => {:feather_fall, true}}}

      assert CmsgMoveFeatherFallAck.handle(message, state).pending_movement_acks == %{}
    end
  end
end
