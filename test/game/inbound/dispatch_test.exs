defmodule ThistleTea.Game.Inbound.DispatchTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Inbound.CmsgPing
  alias ThistleTea.Game.Inbound.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.World.ClientInput

  describe "implemented?/1" do
    test "returns true for implemented opcodes" do
      assert Dispatch.implemented?(Opcodes.get(:CMSG_PING))
    end

    test "returns false for unknown opcodes" do
      refute Dispatch.implemented?(0x123)
    end

    test "returns true for every Vanilla channel command" do
      opcodes = [
        :CMSG_CHANNEL_LIST,
        :CMSG_CHANNEL_PASSWORD,
        :CMSG_CHANNEL_SET_OWNER,
        :CMSG_CHANNEL_OWNER,
        :CMSG_CHANNEL_MODERATOR,
        :CMSG_CHANNEL_UNMODERATOR,
        :CMSG_CHANNEL_MUTE,
        :CMSG_CHANNEL_UNMUTE,
        :CMSG_CHANNEL_INVITE,
        :CMSG_CHANNEL_KICK,
        :CMSG_CHANNEL_BAN,
        :CMSG_CHANNEL_UNBAN,
        :CMSG_CHANNEL_ANNOUNCEMENTS,
        :CMSG_CHANNEL_MODERATE
      ]

      assert Enum.all?(opcodes, &(Opcodes.get(&1) |> Dispatch.implemented?()))
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

  describe "messages/0" do
    test "every decodable client message can be applied as client input" do
      assert Enum.reject(Dispatch.messages(), &ClientInput.impl_for(struct(&1))) == []
    end
  end
end
