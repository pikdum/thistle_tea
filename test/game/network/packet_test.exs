defmodule ThistleTea.Game.Network.PacketTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Packet

  describe "build/2" do
    test "creates packet with opcode and payload" do
      payload = <<1, 2, 3>>
      opcode = 0x123

      packet = Packet.build(payload, opcode)

      assert packet.opcode == opcode
      assert packet.payload == payload
      assert packet.size == byte_size(payload) + 2
    end

    test "calculates size correctly for empty payload" do
      packet = Packet.build(<<>>, 0x100)
      assert packet.size == 2
    end

    test "calculates size correctly for larger payload" do
      payload = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>
      packet = Packet.build(payload, 0x100)
      assert packet.size == 12
    end
  end

  describe "implemented?/1" do
    test "returns true for implemented opcode" do
      assert Packet.implemented?(0x123) == false
    end
  end
end
