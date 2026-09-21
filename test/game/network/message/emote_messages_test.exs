defmodule ThistleTea.Game.Network.Message.EmoteMessagesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.CmsgEmote
  alias ThistleTea.Game.Network.Message.CmsgStandstatechange
  alias ThistleTea.Game.Network.Message.CmsgTextEmote
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Message.SmsgEmote
  alias ThistleTea.Game.Network.Message.SmsgTextEmote
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet

  describe "from_binary/1" do
    test "dispatches all three vanilla client pose messages" do
      for {opcode, payload, expected} <- [
            {:CMSG_EMOTE, <<3::little-32>>, %CmsgEmote{emote: 3}},
            {:CMSG_STANDSTATECHANGE, <<8::little-32>>, %CmsgStandstatechange{animation_state: 8}},
            {:CMSG_TEXT_EMOTE, <<34::little-32, 0xFFFFFFFF::little-32, 42::little-64>>,
             %CmsgTextEmote{text_emote: 34, emote: 0xFFFFFFFF, target: 42}}
          ] do
        assert Dispatch.to_message(%Packet{opcode: Opcodes.get(opcode), payload: payload}) == expected
      end
    end
  end

  describe "to_binary/1" do
    test "encodes targeted Unicode names using byte lengths and preserves emote variation" do
      packet = %SmsgTextEmote{guid: 42, text_emote: 101, emote: 0xFFFFFFFF, name: "Café"}

      assert SmsgTextEmote.to_binary(packet) ==
               <<42::little-64, 101::little-32, 0xFFFFFFFF::little-32, 6::little-32, "Café", 0>>

      assert SmsgEmote.to_binary(%SmsgEmote{emote: 3, guid: 42}) == <<3::little-32, 42::little-64>>
    end
  end
end
