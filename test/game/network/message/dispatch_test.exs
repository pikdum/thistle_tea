defmodule ThistleTea.Game.Network.Message.DispatchTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.CmsgPing
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet

  describe "implemented?/1" do
    test "returns true for implemented opcodes" do
      assert Dispatch.implemented?(Opcodes.get(:CMSG_PING))
    end

    test "returns false for unknown opcodes" do
      refute Dispatch.implemented?(0x123)
    end
  end

  describe "to_message/1" do
    test "parses packets with the matching client message module" do
      opcode = Opcodes.get(:CMSG_PING)

      packet = %Packet{
        opcode: opcode,
        payload: <<1::little-size(32), 2::little-size(32)>>
      }

      assert %CmsgPing{sequence_id: 1, latency: 2} = Dispatch.to_message(packet)
    end
  end
end
