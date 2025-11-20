defmodule ThistleTea.Game.Network.CompressedMove do
  @moduledoc """
  Handles conversion of monster move messages into compressed move format.

  Based on the WOWM format:
  struct CompressedMove {
    u8 size = self.size;
    CompressedMoveOpcode opcode;
    PackedGuid guid;
    if (opcode == SMSG_SPLINE_SET_RUN_SPEED) {
      f32 speed;
    }
    else if (opcode == SMSG_MONSTER_MOVE) {
      MonsterMove monster_move;
    }
    else if (opcode == SMSG_MONSTER_MOVE_TRANSPORT) {
      PackedGuid transport;
      MonsterMove monster_move_transport;
    }
  }
  """

  use ThistleTea.Game.Network.Opcodes, [:SMSG_COMPRESSED_MOVES]

  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message.SmsgMonsterMove
  alias ThistleTea.Game.Network.Packet

  # CompressedMoveOpcode values from the WOWM file
  @smsg_monster_move 0x00DD
  @smsg_monster_move_transport 0x02AE
  @smsg_spline_set_run_speed 0x02FE

  defstruct [
    :opcode,
    :guid,
    :speed,
    :transport,
    :monster_move
  ]

  @doc """
  Converts a SmsgMonsterMove message into a CompressedMove struct.
  """
  def from_monster_move(%SmsgMonsterMove{} = monster_move) do
    %__MODULE__{
      opcode: @smsg_monster_move,
      guid: monster_move.guid,
      monster_move: monster_move
    }
  end

  @doc """
  Converts the CompressedMove to binary format.
  """
  def to_binary(%__MODULE__{opcode: opcode, guid: guid, speed: speed, transport: transport, monster_move: monster_move}) do
    # Start with opcode and packed guid
    base_binary =
      <<opcode::little-size(16)>> <>
        BinaryUtils.pack_guid(guid)

    # Add type-specific data based on opcode
    type_specific_data =
      case opcode do
        @smsg_spline_set_run_speed ->
          <<speed::little-float-size(32)>>

        @smsg_monster_move ->
          # Use MonsterMove binary format (without the GUID that SmsgMonsterMove includes)
          SmsgMonsterMove.monster_move(monster_move)

        @smsg_monster_move_transport ->
          BinaryUtils.pack_guid(transport) <>
            SmsgMonsterMove.monster_move(monster_move)

        _ ->
          <<>>
      end

    # Calculate total size (excluding the size byte itself)
    total_data = base_binary <> type_specific_data
    size = byte_size(total_data)

    # Return with size prefix
    <<size::size(8)>> <> total_data
  end

  @doc """
  Converts a SmsgMonsterMove message into a compressed moves packet.
  Creates a single-move compressed moves packet.

  Can also handle a list of CompressedMove structs for future expansion
  to handle multiple moves in a single packet.
  """
  def to_packet(%SmsgMonsterMove{} = monster_move) do
    compressed_move = from_monster_move(monster_move)
    compressed_move_binary = to_binary(compressed_move)

    %Packet{
      opcode: @smsg_compressed_moves,
      payload: compressed_move_binary
    }
  end

  def to_packet(compressed_moves) when is_list(compressed_moves) do
    payload =
      compressed_moves
      |> Enum.map_join(&to_binary/1)

    %Packet{
      opcode: @smsg_compressed_moves,
      payload: payload
    }
  end
end
