defmodule ThistleTea.Game.Network.Message.ChatMessagesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Inbound.CmsgMessagechat
  alias ThistleTea.Game.Network.Message.SmsgMessagechat
  alias ThistleTea.Game.Network.Message.SmsgNotification

  describe "from_binary/1" do
    test "decodes status commands including empty toggle messages" do
      for type <- [0x14, 0x15], text <- ["", "Café break"] do
        assert CmsgMessagechat.from_binary(<<type::little-32, 0::little-32, text::binary, 0>>) ==
                 %CmsgMessagechat{chat_type: type, language: 0, message: text, target_name: nil}
      end
    end
  end

  describe "to_binary/1" do
    test "encodes a client notification as a terminated string" do
      assert SmsgNotification.to_binary(%SmsgNotification{message: "Café"}) == <<"Café", 0>>
    end

    test "encodes whisper confirmation and status replies with byte lengths" do
      for type <- [6, 7, 0x14, 0x15] do
        packet = %SmsgMessagechat{chat_type: type, language: 0, sender_guid: 42, message: "Café", tag: 2}
        assert SmsgMessagechat.to_binary(packet) == <<type, 0::little-32, 42::little-64, 6::little-32, "Café", 0, 2>>
      end
    end

    test "encodes monster whispers and boss text with the sender's name and target" do
      for chat_type <- [:monster_whisper, :raid_boss_whisper, :raid_boss_emote] do
        packet = SmsgMessagechat.monster(chat_type, "Come, $n.", 42, "Corrupter", 7)
        type = packet.chat_type

        assert type in [0x1A, 0x59, 0x5A]

        assert SmsgMessagechat.to_binary(packet) ==
                 <<type, 0::little-32, 10::little-32, "Corrupter", 0, 7::little-64, 10::little-32, "Come, $n.", 0, 0>>
      end
    end

    test "preserves spoken and addon languages" do
      for language <- [7, 0xFFFFFFFF] do
        packet = %SmsgMessagechat{chat_type: 1, language: language, sender_guid: 42, message: "Hi", tag: 1}

        assert SmsgMessagechat.to_binary(packet) ==
                 <<1, language::little-32, 42::little-64, 42::little-64, 3::little-32, "Hi", 0, 1>>
      end
    end
  end
end
