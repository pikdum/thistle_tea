defmodule ThistleTea.Game.Network.Message.SocialMessagesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Social.Friend

  describe "from_binary/1" do
    test "dispatches the vanilla social requests" do
      cases = [
        {:CMSG_FRIEND_LIST, <<>>, %Message.CmsgFriendList{}},
        {:CMSG_ADD_FRIEND, <<"Café", 0>>, %Message.CmsgAddFriend{name: "Café"}},
        {:CMSG_DEL_FRIEND, <<42::little-64>>, %Message.CmsgDelFriend{guid: 42}},
        {:CMSG_ADD_IGNORE, <<"Café", 0>>, %Message.CmsgAddIgnore{name: "Café"}},
        {:CMSG_DEL_IGNORE, <<42::little-64>>, %Message.CmsgDelIgnore{guid: 42}},
        {:CMSG_CHAT_IGNORED, <<42::little-64, 0>>, %Message.CmsgChatIgnored{guid: 42}}
      ]

      for {opcode, payload, expected} <- cases do
        assert Dispatch.to_message(%Packet{opcode: Opcodes.get(opcode), payload: payload}) == expected
      end
    end
  end

  describe "to_binary/1" do
    test "omits offline friend details and preserves AFK and DND statuses" do
      packet = %Message.SmsgFriendList{
        friends: [
          %Friend{guid: 1},
          %Friend{guid: 2, status: 2, zone: 12, level: 50, class: 8},
          %Friend{guid: 3, status: 4, zone: 14, level: 60, class: 7}
        ]
      }

      assert Message.SmsgFriendList.to_binary(packet) ==
               <<3, 1::little-64, 0, 2::little-64, 2, 12::little-32, 50::little-32, 8::little-32, 3::little-64, 4,
                 14::little-32, 60::little-32, 7::little-32>>

      assert Message.SmsgIgnoreList.to_binary(%Message.SmsgIgnoreList{guids: [1, 2]}) ==
               <<2, 1::little-64, 2::little-64>>
    end

    test "includes details only for online notifications and online additions" do
      friend = %Friend{guid: 42, status: 1, zone: 12, level: 50, class: 8}

      for result <- [2, 6] do
        packet = %Message.SmsgFriendStatus{result: result, friend: friend}

        assert Message.SmsgFriendStatus.to_binary(packet) ==
                 <<result, 42::little-64, 1, 12::little-32, 50::little-32, 8::little-32>>
      end

      for result <- [1, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16] do
        packet = %Message.SmsgFriendStatus{result: result, friend: friend}
        assert Message.SmsgFriendStatus.to_binary(packet) == <<result, 42::little-64>>
      end
    end
  end
end
