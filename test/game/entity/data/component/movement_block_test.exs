defmodule ThistleTea.Game.Entity.Data.Component.MovementBlockTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.MovementBlock

  def base_packet(_context) do
    %{
      base_packet:
        <<0::little-size(32), 1000::little-size(32), 1.0::little-float-size(32), 2.0::little-float-size(32),
          3.0::little-float-size(32), 0.5::little-float-size(32), 0.0::little-float-size(32)>>
    }
  end

  def base_movement_block(_context) do
    %{
      base_movement_block: %MovementBlock{
        update_flag: 0x40,
        movement_flags: 0,
        timestamp: 1000,
        position: {1.0, 2.0, 3.0, 0.5},
        fall_time: 0.0,
        walk_speed: 2.5,
        run_speed: 7.0,
        run_back_speed: 4.5,
        swim_speed: 4.7,
        swim_back_speed: 2.5,
        turn_rate: 3.14
      }
    }
  end

  setup [:base_packet, :base_movement_block]

  describe "from_binary/2" do
    test "parses basic movement packet", context do
      result = MovementBlock.from_binary(context.base_packet)

      assert result.movement_flags == 0
      assert result.timestamp == 1000
      assert result.position == {1.0, 2.0, 3.0, 0.5}
      assert result.fall_time == 0.0
    end

    test "parses with swimming flag" do
      swimming_flag = 0x00200000

      packet =
        <<swimming_flag::little-size(32), 1000::little-size(32), 1.0::little-float-size(32), 2.0::little-float-size(32),
          3.0::little-float-size(32), 0.5::little-float-size(32), 1.25::little-float-size(32),
          0.5::little-float-size(32)>>

      result = MovementBlock.from_binary(packet)

      assert result.movement_flags == swimming_flag
      assert result.pitch == 1.25
      assert result.fall_time == 0.5
    end

    test "parses with jumping flag" do
      jumping_flag = 0x00002000

      packet =
        <<jumping_flag::little-size(32), 1000::little-size(32), 1.0::little-float-size(32), 2.0::little-float-size(32),
          3.0::little-float-size(32), 0.5::little-float-size(32), 0.0::little-float-size(32),
          10.0::little-float-size(32), 0.5::little-float-size(32), 0.866::little-float-size(32),
          5.0::little-float-size(32)>>

      result = MovementBlock.from_binary(packet)

      assert result.movement_flags == jumping_flag
      assert result.z_speed == 10.0
      assert result.cos_angle == 0.5
      assert_in_delta result.sin_angle, 0.866, 0.001
      assert result.xy_speed == 5.0
    end

    test "parses with spline elevation flag" do
      spline_flag = 0x04000000

      packet =
        <<spline_flag::little-size(32), 1000::little-size(32), 1.0::little-float-size(32), 2.0::little-float-size(32),
          3.0::little-float-size(32), 0.5::little-float-size(32), 0.0::little-float-size(32),
          5.5::little-float-size(32)>>

      result = MovementBlock.from_binary(packet)

      assert result.movement_flags == spline_flag
      assert result.spline_elevation == 5.5
    end

    test "merges with accumulator" do
      acc = %MovementBlock{walk_speed: 2.5}

      packet =
        <<0::little-size(32), 1000::little-size(32), 1.0::little-float-size(32), 2.0::little-float-size(32),
          3.0::little-float-size(32), 0.5::little-float-size(32), 0.0::little-float-size(32)>>

      result = MovementBlock.from_binary(packet, acc)

      assert result.position == {1.0, 2.0, 3.0, 0.5}
      assert result.walk_speed == 2.5
    end
  end

  describe "to_binary/1" do
    test "serializes minimal movement block", context do
      result = MovementBlock.to_binary(context.base_movement_block)

      assert is_binary(result)
      assert byte_size(result) > 0
    end

    test "includes swimming data when flag set", context do
      movement_block = %{context.base_movement_block | movement_flags: 0x00200000, pitch: 1.25, fall_time: 0.5}

      result = MovementBlock.to_binary(movement_block)

      assert is_binary(result)
      assert byte_size(result) > 0
    end

    test "includes jumping data when flag set", context do
      movement_block = %{
        context.base_movement_block
        | movement_flags: 0x00002000,
          z_speed: 10.0,
          cos_angle: 0.5,
          sin_angle: 0.866,
          xy_speed: 5.0
      }

      result = MovementBlock.to_binary(movement_block)

      assert is_binary(result)
      assert byte_size(result) > 0
    end

    test "includes spline elevation when flag set", context do
      movement_block = %{context.base_movement_block | movement_flags: 0x04000000, spline_elevation: 5.5}

      result = MovementBlock.to_binary(movement_block)

      assert is_binary(result)
      assert byte_size(result) > 0
    end
  end
end
