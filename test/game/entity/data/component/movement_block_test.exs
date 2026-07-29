defmodule ThistleTea.Game.Entity.Data.Component.MovementBlockTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Network.BinaryUtils

  def base_packet(_context) do
    %{
      base_packet:
        <<0::little-size(32), 1000::little-size(32), 1.0::little-float-size(32), 2.0::little-float-size(32),
          3.0::little-float-size(32), 0.5::little-float-size(32), 0::little-size(32)>>
    }
  end

  def base_movement_block(_context) do
    %{
      base_movement_block: %MovementBlock{
        update_flag: 0x40,
        movement_flags: 0,
        timestamp: 1000,
        position: {1.0, 2.0, 3.0, 0.5},
        fall_time: 0,
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
      assert result.fall_time == 0
    end

    test "parses with swimming flag" do
      swimming_flag = 0x00200000

      packet =
        <<swimming_flag::little-size(32), 1000::little-size(32), 1.0::little-float-size(32), 2.0::little-float-size(32),
          3.0::little-float-size(32), 0.5::little-float-size(32), 1.25::little-float-size(32), 500::little-size(32)>>

      result = MovementBlock.from_binary(packet)

      assert result.movement_flags == swimming_flag
      assert result.pitch == 1.25
      assert result.fall_time == 500
    end

    test "parses transport guid and local position" do
      transport_flag = 0x02000000
      transport_guid = 0x1FC000000000BEEF

      packet =
        <<transport_flag::little-size(32), 1000::little-size(32)>> <>
          vector({1.0, 2.0, 3.0}) <>
          <<0.5::little-float-size(32), transport_guid::little-size(64)>> <>
          vector({4.0, 5.0, 6.0}) <>
          <<0.75::little-float-size(32), 500::little-size(32)>>

      result = MovementBlock.from_binary(packet)

      assert result.transport_guid == transport_guid
      assert result.transport_position == {4.0, 5.0, 6.0, 0.75}
      assert result.fall_time == 500
    end

    test "parses a captured zeppelin movement packet" do
      packet =
        <<9, 0, 0, 2, 24, 11, 112, 5, 1, 127, 171, 68, 221, 230, 144, 197, 90, 254, 91, 66, 32, 139, 142, 62, 232, 171,
          2, 0, 0, 0, 192, 31, 22, 148, 45, 193, 127, 162, 193, 192, 241, 227, 134, 193, 94, 136, 140, 64, 24, 5, 0, 0>>

      result = MovementBlock.from_binary(packet)

      assert result.transport_guid == 0x1FC000000002ABE8

      assert result.transport_position ==
               {-10.848653793334961, -6.051085948944092, -16.861299514770508, 4.391646385192871}

      assert result.fall_time == 1304
    end

    test "clears stale transport data after leaving a transport", context do
      movement_block = %{
        context.base_movement_block
        | transport_guid: 0x1FC000000000BEEF,
          transport_position: {4.0, 5.0, 6.0, 0.75}
      }

      result = MovementBlock.from_binary(context.base_packet, movement_block)

      assert result.transport_guid == nil
      assert result.transport_position == nil
    end

    test "parses with jumping flag" do
      jumping_flag = 0x00002000

      packet =
        <<jumping_flag::little-size(32), 1000::little-size(32), 1.0::little-float-size(32), 2.0::little-float-size(32),
          3.0::little-float-size(32), 0.5::little-float-size(32), 0::little-size(32), 10.0::little-float-size(32),
          0.5::little-float-size(32), 0.866::little-float-size(32), 5.0::little-float-size(32)>>

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
          3.0::little-float-size(32), 0.5::little-float-size(32), 0::little-size(32), 5.5::little-float-size(32)>>

      result = MovementBlock.from_binary(packet)

      assert result.movement_flags == spline_flag
      assert result.spline_elevation == 5.5
    end

    test "merges with accumulator" do
      acc = %MovementBlock{walk_speed: 2.5}

      packet =
        <<0::little-size(32), 1000::little-size(32), 1.0::little-float-size(32), 2.0::little-float-size(32),
          3.0::little-float-size(32), 0.5::little-float-size(32), 0::little-size(32)>>

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

    test "serializes MaNGOS-style idle unit create movement block", context do
      movement_block = %{context.base_movement_block | update_flag: 0x70}

      result = MovementBlock.to_binary(movement_block)

      assert result ==
               <<0x70, 0::little-size(32), 1000::little-size(32)>> <>
                 vector({1.0, 2.0, 3.0}) <>
                 <<0.5::little-float-size(32), 0::little-size(32), 2.5::little-float-size(32),
                   7.0::little-float-size(32), 4.5::little-float-size(32), 4.7::little-float-size(32),
                   2.5::little-float-size(32), 3.14::little-float-size(32), 1::little-size(32)>>
    end

    test "includes swimming data when flag set", context do
      movement_block = %{context.base_movement_block | movement_flags: 0x00200000, pitch: 1.25, fall_time: 500}

      result = MovementBlock.to_binary(movement_block)

      assert is_binary(result)
      assert byte_size(result) > 0
    end

    test "serializes transport guid and local position", context do
      transport_guid = 0x1FC000000000BEEF

      movement_block = %{
        context.base_movement_block
        | update_flag: 0x20,
          movement_flags: 0x02000000,
          transport_guid: transport_guid,
          transport_position: {4.0, 5.0, 6.0, 0.75}
      }

      result = MovementBlock.to_binary(movement_block)

      expected =
        <<0x20, 0x02000000::little-size(32), 1000::little-size(32)>> <>
          vector({1.0, 2.0, 3.0}) <>
          <<0.5::little-float-size(32), transport_guid::little-size(64)>> <>
          vector({4.0, 5.0, 6.0}) <>
          <<0.75::little-float-size(32), 0::little-size(32), 2.5::little-float-size(32), 7.0::little-float-size(32),
            4.5::little-float-size(32), 4.7::little-float-size(32), 2.5::little-float-size(32),
            3.14::little-float-size(32)>>

      assert result == expected
      assert MovementBlock.from_binary(binary_part(result, 1, byte_size(result) - 25)).transport_guid == transport_guid
    end

    test "serializes melee target as a packed guid", context do
      target_guid = 0xF130000100000004
      movement_block = %{context.base_movement_block | update_flag: 0x44, target_guid: target_guid}

      result = MovementBlock.to_binary(movement_block)

      assert result ==
               <<0x44>> <>
                 vector({1.0, 2.0, 3.0}) <>
                 <<0.5::little-float-size(32)>> <>
                 BinaryUtils.pack_guid(target_guid)
    end

    test "serializes a transport from its stationary position and current progress", context do
      movement_block = %{
        context.base_movement_block
        | update_flag: 0x52,
          position: {100.0, 200.0, 300.0, 1.0},
          stationary_position: {4.0, 5.0, 6.0, 0.75},
          transport_progress_in_ms: 12_345
      }

      result = MovementBlock.to_binary(movement_block)

      assert result ==
               <<0x52>> <>
                 vector({4.0, 5.0, 6.0}) <>
                 <<0.75::little-float-size(32), 1::little-size(32), 12_345::little-size(32)>>
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

    test "serializes active spline create data", context do
      movement_block = %{
        context.base_movement_block
        | update_flag: 0x20,
          movement_flags: 0x00400001,
          spline_flags: 0x100,
          time_passed: 50,
          duration: 1_000,
          spline_id: 7,
          spline_start_position: {0.0, 0.0, 0.0},
          spline_nodes: [{1.0, 0.0, 0.0}, {2.0, 0.0, 0.0}]
      }

      result = MovementBlock.to_binary(movement_block)

      prefix_size = 1 + 4 + 4 + 16 + 4 + 24

      active_spline_binary = binary_part(result, prefix_size, byte_size(result) - prefix_size)

      assert active_spline_binary ==
               <<0x100::little-size(32), 50::little-size(32), 1_000::little-size(32), 7::little-size(32),
                 5::little-size(32)>> <>
                 vector({-1.0, 0.0, 0.0}) <>
                 vector({0.0, 0.0, 0.0}) <>
                 vector({1.0, 0.0, 0.0}) <>
                 vector({2.0, 0.0, 0.0}) <>
                 vector({2.0, 0.0, 0.02}) <>
                 vector({2.0, 0.0, 0.0})
    end

    test "strips stale spline movement flags without active spline data", context do
      movement_block = %{
        context.base_movement_block
        | update_flag: 0x20,
          movement_flags: 0x00400101,
          spline_nodes: [],
          duration: 0,
          spline_id: nil
      }

      result = MovementBlock.to_binary(movement_block)

      prefix_size = 1 + 4 + 4 + 16 + 4 + 24

      <<0x20, 0x100::little-size(32), _rest::binary>> = result
      assert byte_size(result) == prefix_size
    end
  end

  describe "refresh_timestamp/2" do
    test "stamps living blocks without a client timestamp", context do
      movement_block = %{context.base_movement_block | update_flag: 0x70, timestamp: 0}

      assert MovementBlock.refresh_timestamp(movement_block, 5000).timestamp == 6000
    end

    test "stamps living blocks with a nil timestamp", context do
      movement_block = %{context.base_movement_block | update_flag: 0x20, timestamp: nil}

      assert MovementBlock.refresh_timestamp(movement_block, 5000).timestamp == 6000
    end

    test "keeps client-provided timestamps", context do
      movement_block = %{context.base_movement_block | update_flag: 0x70, timestamp: 1234}

      assert MovementBlock.refresh_timestamp(movement_block, 5000).timestamp == 1234
    end

    test "ignores non-living blocks", context do
      movement_block = %{context.base_movement_block | update_flag: 0x40, timestamp: 0}

      assert MovementBlock.refresh_timestamp(movement_block, 5000).timestamp == 0
    end
  end

  describe "translating?/1" do
    test "detects forward, backward and strafe motion", context do
      for flags <- [0x1, 0x2, 0x4, 0x8] do
        assert MovementBlock.translating?(%{context.base_movement_block | movement_flags: flags})
      end
    end

    test "ignores turning and jumping in place", context do
      for flags <- [0x0, 0x10, 0x20, 0x2000] do
        refute MovementBlock.translating?(%{context.base_movement_block | movement_flags: flags})
      end
    end
  end

  describe "airborne?/1" do
    test "detects jumping and falling", context do
      for flags <- [0x2000, 0x4000] do
        assert MovementBlock.airborne?(%{context.base_movement_block | movement_flags: flags})
      end
    end

    test "ignores grounded movement", context do
      assert MovementBlock.airborne?(%{context.base_movement_block | movement_flags: 0x1}) == false
    end
  end

  describe "position_changed?/2" do
    test "uses deck-local coordinates while attached to the same transport" do
      previous = %MovementBlock{
        position: {10.0, 20.0, 30.0, 0.0},
        transport_guid: 123,
        transport_position: {1.0, 2.0, 3.0, 0.0}
      }

      current = %{
        previous
        | position: {40.0, 50.0, 60.0, 0.0},
          transport_position: {1.0, 2.0, 3.0, 1.0}
      }

      refute MovementBlock.position_changed?(previous, current)
      assert MovementBlock.position_changed?(previous, %{current | transport_position: {2.0, 2.0, 3.0, 1.0}})
    end
  end

  defp vector({x, y, z}) do
    <<x::little-float-size(32), y::little-float-size(32), z::little-float-size(32)>>
  end
end
