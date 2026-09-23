defmodule ThistleTea.Game.Network.Message.RaidInfoTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.CmsgRequestRaidInfo
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Message.SmsgInstanceSaveCreated
  alias ThistleTea.Game.Network.Message.SmsgRaidInstanceInfo
  alias ThistleTea.Game.Network.Opcodes

  describe "CMSG_REQUEST_RAID_INFO" do
    test "dispatches the native empty request and replies with an empty list for an unsaved player" do
      assert Dispatch.implemented?(Opcodes.get(:CMSG_REQUEST_RAID_INFO))
      message = CmsgRequestRaidInfo.from_binary(<<>>)
      state = %{ready: true, guid: System.unique_integer([:positive])}
      assert CmsgRequestRaidInfo.handle(message, state) == state
      assert_receive {:"$gen_cast", {:send_packet, %SmsgRaidInstanceInfo{raids: []}}}
      assert CmsgRequestRaidInfo.handle(message, %{ready: false}) == %{ready: false}
      refute_receive {:"$gen_cast", {:send_packet, _}}
    end
  end

  describe "SMSG_RAID_INSTANCE_INFO" do
    test "encodes vanilla map, seconds remaining, and 32-bit instance IDs" do
      raids = [
        %{map_id: 249, seconds_remaining: 60, instance_id: 7},
        %{map_id: 309, seconds_remaining: 3, instance_id: 8}
      ]

      assert SmsgRaidInstanceInfo.to_binary(%SmsgRaidInstanceInfo{raids: raids}) ==
               <<2::little-32, 249::little-32, 60::little-32, 7::little-32, 309::little-32, 3::little-32, 8::little-32>>

      assert SmsgRaidInstanceInfo.to_binary(%SmsgRaidInstanceInfo{}) == <<0::little-32>>
      assert SmsgInstanceSaveCreated.to_binary(%SmsgInstanceSaveCreated{}) == <<0::little-32>>
    end
  end
end
