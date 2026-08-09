defmodule ThistleTea.Game.Network.Message.MsgMoveTeleportTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message.MsgMoveTeleport

  describe "to_binary/1" do
    test "encodes the packed guid followed directly by stationary movement info" do
      guid = 0xF130000100000004

      movement_block = %MovementBlock{
        movement_flags: 0,
        timestamp: 12_345,
        position: {4032.73, -3366.51, 115.063, 0.0},
        fall_time: 0
      }

      message = %MsgMoveTeleport{guid: guid, movement_block: movement_block}

      expected =
        BinaryUtils.pack_guid(guid) <>
          <<
            0::little-size(32),
            12_345::little-size(32),
            4032.73::little-float-size(32),
            -3366.51::little-float-size(32),
            115.063::little-float-size(32),
            0.0::little-float-size(32),
            0::little-size(32)
          >>

      assert MsgMoveTeleport.to_binary(message) == expected
      assert MsgMoveTeleport.opcode() == 0x0C5
    end

    test "retains optional movement-info fields and nonzero orientation" do
      movement_flags = 0x02000000 ||| 0x00200000 ||| 0x00002000 ||| 0x04000000
      transport_guid = 0x1FC000000000BEEF

      movement_block = %MovementBlock{
        movement_flags: movement_flags,
        timestamp: 77,
        position: {1.0, 2.0, 3.0, 4.0},
        transport_guid: transport_guid,
        transport_position: {5.0, 6.0, 7.0, 0.5},
        pitch: 0.25,
        fall_time: 9,
        z_speed: 10.0,
        cos_angle: 0.75,
        sin_angle: 0.5,
        xy_speed: 8.0,
        spline_elevation: 1.25
      }

      message = %MsgMoveTeleport{guid: 0xAABB, movement_block: movement_block}

      expected =
        BinaryUtils.pack_guid(0xAABB) <>
          <<
            movement_flags::little-size(32),
            77::little-size(32),
            1.0::little-float-size(32),
            2.0::little-float-size(32),
            3.0::little-float-size(32),
            4.0::little-float-size(32),
            transport_guid::little-size(64),
            5.0::little-float-size(32),
            6.0::little-float-size(32),
            7.0::little-float-size(32),
            0.5::little-float-size(32),
            0.25::little-float-size(32),
            9::little-size(32),
            10.0::little-float-size(32),
            0.75::little-float-size(32),
            0.5::little-float-size(32),
            8.0::little-float-size(32),
            1.25::little-float-size(32)
          >>

      assert MsgMoveTeleport.to_binary(message) == expected
    end
  end
end
