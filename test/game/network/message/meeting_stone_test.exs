defmodule ThistleTea.Game.Network.Message.MeetingStoneTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Packet

  describe "to_message/1" do
    test "dispatches all three vanilla client requests" do
      guid = 0xF110_0001_0000_0002

      for {opcode, payload, expected} <- [
            {0x292, <<guid::little-size(64)>>, %Message.CmsgMeetingstoneJoin{guid: guid}},
            {0x293, <<>>, %Message.CmsgMeetingstoneLeave{}},
            {0x296, <<>>, %Message.CmsgMeetingstoneInfo{}}
          ] do
        assert Dispatch.implemented?(opcode)
        assert Dispatch.to_message(%Packet{opcode: opcode, payload: payload}) == expected
        assert Message.handle(expected, %{ready: false}) == %{ready: false}
      end
    end
  end

  describe "to_binary/1" do
    test "encodes queue status, failure, addition, and empty notifications" do
      assert Message.to_binary(%Message.SmsgMeetingstoneSetqueue{area: 1581, status: 1}) == <<45, 6, 0, 0, 1>>
      assert Message.to_binary(%Message.SmsgMeetingstoneJoinfailed{reason: 3}) == <<3>>
      assert Message.to_binary(%Message.SmsgMeetingstoneMemberAdded{guid: 7}) == <<7::little-size(64)>>
      assert Message.to_binary(%Message.SmsgMeetingstoneComplete{}) == <<>>
      assert Message.to_binary(%Message.SmsgMeetingstoneInProgress{}) == <<>>
    end
  end
end
