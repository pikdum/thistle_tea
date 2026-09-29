defmodule ThistleTea.Game.Network.SendTest do
  use ExUnit.Case, async: true
  use ThistleTea.Game.Network.Opcodes, [:SMSG_UPDATE_OBJECT, :SMSG_COMPRESSED_UPDATE_OBJECT, :SMSG_EMOTE]

  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Network.Send

  describe "compress/1" do
    test "compresses update-object payloads over 128 bytes behind their original size" do
      payload = :binary.copy(<<1, 2, 3, 4>>, 40)

      assert %Packet{opcode: @smsg_compressed_update_object, payload: <<160::little-size(32), compressed::binary>>} =
               Send.compress(%Packet{opcode: @smsg_update_object, payload: payload})

      assert :zlib.uncompress(compressed) == payload
    end

    test "keeps update-object payloads of 128 bytes or fewer uncompressed" do
      packet = %Packet{opcode: @smsg_update_object, payload: :binary.copy(<<7>>, 128)}

      assert Send.compress(packet) == packet
    end

    test "leaves other opcodes uncompressed" do
      packet = %Packet{opcode: @smsg_emote, payload: :binary.copy(<<7>>, 512)}

      assert Send.compress(packet) == packet
    end
  end
end
