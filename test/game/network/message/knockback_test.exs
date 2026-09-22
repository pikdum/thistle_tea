defmodule ThistleTea.Game.Network.Message.KnockbackTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Network.Packet

  setup [:launch]

  describe "to_binary/1" do
    test "encodes controller and observer packets in vanilla field order", %{packet: packet, movement: movement} do
      assert Message.SmsgMoveKnockBack.to_binary(packet) ==
               BinaryUtils.pack_guid(42) <>
                 <<0::little-size(32), 0.6::little-float-size(32), 0.8::little-float-size(32),
                   12.0::little-float-size(32), -7.0::little-float-size(32)>>

      payload = MovementBlock.movement_info_to_binary(movement)
      observer = Message.MsgMove.to_packet(42, payload, 0xF1)
      assert %Message.MsgMoveKnockBack{} = observer

      assert Message.to_binary(observer) ==
               BinaryUtils.pack_guid(42) <>
                 payload <>
                 <<movement.cos_angle::little-float-size(32), movement.sin_angle::little-float-size(32),
                   12.0::little-float-size(32), -7.0::little-float-size(32)>>
    end
  end

  describe "acknowledge_knockback/4" do
    test "dispatches the native acknowledgement and consumes it once", %{state: state, movement: movement} do
      payload = MovementBlock.movement_info_to_binary(movement)

      assert %Message.CmsgMoveKnockBackAck{guid: 42, counter: 0, movement_payload: ^payload} =
               Dispatch.to_message(Packet.build(<<42::little-size(64), 0::little-size(32), payload::binary>>, 0xF0))

      assert {:ok, consumed} = MovementControl.acknowledge_knockback(state, 42, 0, movement)
      assert consumed.pending_movement_acks == %{}
      assert {:error, ^consumed} = MovementControl.acknowledge_knockback(consumed, 42, 0, movement)
    end

    test "rejects wrong mover, counter, impulse, or movement flags", %{state: state, movement: movement} do
      for {guid, counter, received} <- [
            {43, 0, movement},
            {42, 1, movement},
            {42, 0, %{movement | movement_flags: 0}},
            {42, 0, %{movement | cos_angle: 0.8, sin_angle: 0.6}},
            {42, 0, %{movement | xy_speed: 24.0}},
            {42, 0, %{movement | z_speed: 7.0}}
          ] do
        assert {:error, ^state} = MovementControl.acknowledge_knockback(state, guid, counter, received)
      end
    end

    test "teleport and worldport invalidate earlier launches", %{state: state, movement: movement} do
      {teleport, teleported} = MovementControl.prepare(%Message.MsgMoveTeleportAck{guid: 42}, state)
      assert teleported.pending_movement_acks == %{teleport.counter => :teleport}
      assert {:error, ^teleported} = MovementControl.acknowledge_knockback(teleported, 42, 0, movement)
      {_, worldport} = MovementControl.prepare(%Message.SmsgNewWorld{}, state)
      assert worldport.pending_movement_acks == %{}
    end
  end

  defp launch(_) do
    packet = %Message.SmsgMoveKnockBack{
      guid: 42,
      cos_angle: 0.6,
      sin_angle: 0.8,
      horizontal_speed: 12.0,
      vertical_speed: -7.0
    }

    {packet, state} = MovementControl.prepare(packet, %State{guid: 42})

    movement = %MovementBlock{
      position: {1.0, 2.0, 3.0, 0.0},
      movement_flags: 0x2000,
      timestamp: 100,
      fall_time: 0,
      cos_angle: 0.6,
      sin_angle: 0.8,
      xy_speed: 12.0,
      z_speed: -7.0
    }

    movement = movement |> MovementBlock.movement_info_to_binary() |> MovementBlock.from_binary()
    %{packet: packet, state: state, movement: movement}
  end
end
