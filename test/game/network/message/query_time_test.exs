defmodule ThistleTea.Game.Network.Message.QueryTimeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Registry
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet

  describe "handle/2" do
    test "answers an empty time query with current Unix seconds for the ready player" do
      guid = System.unique_integer([:positive])
      Registry.register(guid)
      state = %{ready: true, guid: guid}
      packet = %Packet{opcode: Opcodes.get(:CMSG_QUERY_TIME), payload: <<>>}
      assert %Message.CmsgQueryTime{} = message = Dispatch.to_message(packet)
      before = System.system_time(:second)
      assert Message.CmsgQueryTime.handle(message, state) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgQueryTimeResponse{time: time} = response}}
      assert time >= before
      assert time <= System.system_time(:second)
      assert Message.SmsgQueryTimeResponse.to_binary(response) == <<time::little-size(32)>>

      state = %{state | ready: false}
      assert Message.CmsgQueryTime.handle(message, state) == state
      refute_receive {:"$gen_cast", {:send_packet, _}}
    end
  end
end
