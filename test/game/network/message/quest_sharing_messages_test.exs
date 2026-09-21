defmodule ThistleTea.Game.Network.Message.QuestSharingMessagesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet

  describe "from_binary/1" do
    test "dispatches sharing, confirmation, and result requests" do
      cases = [
        {:CMSG_PUSHQUESTTOPARTY, <<7::little-32>>, %Message.CmsgPushquesttoparty{quest_id: 7}},
        {:CMSG_QUEST_CONFIRM_ACCEPT, <<7::little-32>>, %Message.CmsgQuestConfirmAccept{quest_id: 7}},
        {:MSG_QUEST_PUSH_RESULT, <<42::little-64, 3>>, %Message.MsgQuestPushResultClient{guid: 42, result: 3}}
      ]

      for {opcode, payload, expected} <- cases do
        assert Dispatch.to_message(%Packet{opcode: Opcodes.get(opcode), payload: payload}) == expected
      end
    end
  end

  describe "to_binary/1" do
    test "encodes every result and the confirmation title before the sharer" do
      for result <- 0..8 do
        assert Message.MsgQuestPushResult.to_binary(%Message.MsgQuestPushResult{guid: 42, result: result}) ==
                 <<42::little-64, result>>
      end

      assert Message.SmsgQuestConfirmAccept.to_binary(%Message.SmsgQuestConfirmAccept{
               quest_id: 7,
               title: "Café",
               sharer_guid: 42
             }) == <<7::little-32, "Café", 0, 42::little-64>>
    end
  end
end
