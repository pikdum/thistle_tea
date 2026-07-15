defmodule ThistleTea.Game.Network.Message.SmsgChannelListTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Chat.Channel.Member
  alias ThistleTea.Game.Network.Message.SmsgChannelList

  describe "to_binary/1" do
    test "serializes channel flags and members" do
      message = %SmsgChannelList{
        channel_name: "Custom",
        channel_flags: 0x01,
        members: [%Member{guid: 42, flags: 0x03}, %Member{guid: 84, flags: 0x08}]
      }

      assert SmsgChannelList.to_binary(message) ==
               <<"Custom", 0, 0x01, 2::little-size(32), 42::little-size(64), 0x03, 84::little-size(64), 0x08>>
    end
  end
end
