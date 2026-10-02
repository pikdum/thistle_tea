defmodule ThistleTea.Game.Inbound.ClientReportsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Inbound.CmsgBug
  alias ThistleTea.Game.Inbound.CmsgGmsurveySubmit
  alias ThistleTea.Game.Inbound.CmsgQuestlogSwapQuest
  alias ThistleTea.Game.Inbound.Dispatch
  alias ThistleTea.Game.Network.Message.MsgLookingForGroup
  alias ThistleTea.Game.Network.Message.SmsgMountspecialAnim
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet

  defp message(opcode, payload), do: Dispatch.to_message(%Packet{opcode: Opcodes.get(opcode), payload: payload})

  describe "CmsgBug.from_binary/1" do
    test "reads a suggestion's text and category" do
      payload = <<1::little-32, 9::little-32, "Add mail", 0, 4::little-32, "Map", 0>>

      assert %CmsgBug{suggestion?: true, content: "Add mail", type: "Map"} = message(:CMSG_BUG, payload)
    end
  end

  describe "CmsgGmsurveySubmit.from_binary/1" do
    test "reads answers up to the terminator and the closing comment" do
      payload =
        <<2::little-32, 30::little-32, 4, "fast", 0, 31::little-32, 1, 0, 0::little-32, "thanks", 0>>

      assert %CmsgGmsurveySubmit{survey_id: 2, answers: [{30, 4, "fast"}, {31, 1, ""}], comment: "thanks"} =
               message(:CMSG_GMSURVEY_SUBMIT, payload)
    end
  end

  describe "CmsgQuestlogSwapQuest.from_binary/1" do
    test "reads both slots" do
      assert %CmsgQuestlogSwapQuest{slot1: 2, slot2: 7} = message(:CMSG_QUESTLOG_SWAP_QUEST, <<2, 7>>)
    end
  end

  describe "server messages" do
    test "encode the mounted unit and an empty group listing" do
      assert SmsgMountspecialAnim.to_binary(%SmsgMountspecialAnim{guid: 5}) == <<5::little-64>>
      assert MsgLookingForGroup.to_binary(%MsgLookingForGroup{}) == <<0::little-32>>
    end
  end
end
