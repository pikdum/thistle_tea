defmodule ThistleTea.Game.Network.Message.RaidMessagesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet

  describe "from_binary/1" do
    test "dispatches the vanilla raid commands and optional ready-check payload" do
      cases = [
        {:CMSG_GROUP_RAID_CONVERT, <<>>, %Message.CmsgGroupRaidConvert{}},
        {:CMSG_GROUP_CHANGE_SUB_GROUP, <<"Café", 0, 7>>, %Message.CmsgGroupChangeSubGroup{name: "Café", subgroup: 7}},
        {:CMSG_GROUP_SWAP_SUB_GROUP, <<"First", 0, "Second", 0>>,
         %Message.CmsgGroupSwapSubGroup{first: "First", second: "Second"}},
        {:CMSG_GROUP_ASSISTANT_LEADER, <<42::little-64, 1>>,
         %Message.CmsgGroupAssistantLeader{guid: 42, enabled?: true}},
        {:MSG_RAID_TARGET_UPDATE, <<255>>, %Message.MsgRaidTargetUpdate{icon: 255}},
        {:MSG_RAID_TARGET_UPDATE, <<7, 42::little-64>>, %Message.MsgRaidTargetUpdate{icon: 7, target: 42}},
        {:MSG_RAID_READY_CHECK, <<>>, %Message.MsgRaidReadyCheck{}},
        {:MSG_RAID_READY_CHECK, <<0>>, %Message.MsgRaidReadyCheck{ready?: false}},
        {:MSG_RAID_READY_CHECK, <<1>>, %Message.MsgRaidReadyCheck{ready?: true}}
      ]

      for {opcode, payload, expected} <- cases do
        assert Dispatch.to_message(%Packet{opcode: Opcodes.get(opcode), payload: payload}) == expected
      end
    end
  end

  describe "to_binary/1" do
    test "encodes marker deltas, full lists, and ready-check requests and answers" do
      assert Message.MsgRaidTargetUpdateResponse.to_binary(%Message.MsgRaidTargetUpdateResponse{icon: 7, target: 42}) ==
               <<0, 7, 42::little-64>>

      assert Message.MsgRaidTargetUpdateResponse.to_binary(%Message.MsgRaidTargetUpdateResponse{
               icons: [{0, 11}, {7, 42}]
             }) ==
               <<1, 0, 11::little-64, 7, 42::little-64>>

      assert Message.MsgRaidTargetUpdateResponse.to_binary(%Message.MsgRaidTargetUpdateResponse{icons: []}) == <<1>>
      assert Message.MsgRaidReadyCheckResponse.to_binary(%Message.MsgRaidReadyCheckResponse{}) == <<>>

      for {ready?, flag} <- [{false, 0}, {true, 1}] do
        response = %Message.MsgRaidReadyCheckResponse{guid: 42, ready?: ready?}
        assert Message.MsgRaidReadyCheckResponse.to_binary(response) == <<42::little-64, flag>>
      end
    end
  end
end
