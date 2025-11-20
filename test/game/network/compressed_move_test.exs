defmodule ThistleTea.Game.Network.CompressedMoveTest do
  use ExUnit.Case

  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.CompressedMove
  alias ThistleTea.Game.Network.Message.SmsgMonsterMove
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet

  @smsg_compressed_moves Opcodes.get(:SMSG_COMPRESSED_MOVES)

  describe "from_monster_move/1" do
    test "creates CompressedMove from SmsgMonsterMove" do
      monster_move = %SmsgMonsterMove{
        guid: 123,
        spline_point: {1.0, 2.0, 3.0},
        spline_id: 1,
        move_type: 0,
        spline_flags: 0,
        duration: 1000,
        splines: [{4.0, 5.0, 6.0}, {7.0, 8.0, 9.0}]
      }

      compressed_move = CompressedMove.from_monster_move(monster_move)

      # SMSG_MONSTER_MOVE
      assert compressed_move.opcode == 0x00DD
      assert compressed_move.guid == 123
      assert compressed_move.monster_move == monster_move
    end
  end

  describe "to_binary/1" do
    test "generates correct binary format" do
      monster_move = %SmsgMonsterMove{
        guid: 123,
        spline_point: {1.0, 2.0, 3.0},
        spline_id: 1,
        move_type: 0,
        spline_flags: 0,
        duration: 1000,
        splines: [{4.0, 5.0, 6.0}, {7.0, 8.0, 9.0}]
      }

      compressed_move = CompressedMove.from_monster_move(monster_move)
      binary = CompressedMove.to_binary(compressed_move)

      # Should start with size byte, then opcode (2 bytes), then packed guid
      <<size::8, opcode::little-16, _rest::binary>> = binary

      # SMSG_MONSTER_MOVE
      assert opcode == 0x00DD
      # Size excludes the size byte itself
      assert size == byte_size(binary) - 1
      # Should have at least size + opcode + some guid data
      assert byte_size(binary) > 4
    end

    test "monster move binary excludes GUID (different from SmsgMonsterMove.to_binary)" do
      monster_move = %SmsgMonsterMove{
        guid: 123,
        spline_point: {1.0, 2.0, 3.0},
        spline_id: 1,
        move_type: 0,
        spline_flags: 0,
        duration: 1000,
        splines: [{4.0, 5.0, 6.0}]
      }

      # Original SmsgMonsterMove binary includes the packed GUID
      original_binary = SmsgMonsterMove.to_binary(monster_move)

      # Compressed move binary should be different (and smaller) because it excludes the GUID
      compressed_move = CompressedMove.from_monster_move(monster_move)
      compressed_binary = CompressedMove.to_binary(compressed_move)

      # The compressed binary should be larger than just the monster move part
      # but should contain the GUID in a different location
      # Has size + opcode + packed guid + monster move data
      assert byte_size(compressed_binary) > 10
      # Should be different format
      assert compressed_binary != original_binary

      # Verify that SmsgMonsterMove.monster_move/1 + packed GUID equals SmsgMonsterMove.to_binary/1
      monster_move_only = SmsgMonsterMove.monster_move(monster_move)
      packed_guid = BinaryUtils.pack_guid(monster_move.guid)
      reconstructed = packed_guid <> monster_move_only
      assert reconstructed == original_binary
    end
  end

  describe "to_packet/1" do
    test "creates packet from SmsgMonsterMove" do
      monster_move = %SmsgMonsterMove{
        guid: 123,
        spline_point: {1.0, 2.0, 3.0},
        spline_id: 1,
        move_type: 0,
        spline_flags: 0,
        duration: 1000,
        splines: [{4.0, 5.0, 6.0}]
      }

      packet = CompressedMove.to_packet(monster_move)

      assert %Packet{} = packet
      assert packet.opcode == @smsg_compressed_moves
      assert is_binary(packet.payload)
      assert byte_size(packet.payload) > 0
    end

    test "creates packet from list of compressed moves" do
      monster_move = %SmsgMonsterMove{
        guid: 123,
        spline_point: {1.0, 2.0, 3.0},
        spline_id: 1,
        move_type: 0,
        spline_flags: 0,
        duration: 1000,
        splines: [{4.0, 5.0, 6.0}]
      }

      compressed_moves = [
        CompressedMove.from_monster_move(monster_move),
        CompressedMove.from_monster_move(%{monster_move | guid: 456})
      ]

      packet = CompressedMove.to_packet(compressed_moves)

      assert %Packet{} = packet
      assert packet.opcode == @smsg_compressed_moves
      assert is_binary(packet.payload)
      assert byte_size(packet.payload) > byte_size(CompressedMove.to_packet(monster_move).payload)
    end
  end
end
