defmodule ThistleTea.Game.Network.Message.MsgRandomRollTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Message.MsgRandomRoll
  alias ThistleTea.Game.Network.Message.MsgRandomRollResponse
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.World.Inbound

  describe "from_binary/1" do
    test "dispatches unsigned vanilla bounds without accepting a caller-supplied identity" do
      payload = <<0, 0, 0, 0, 64, 66, 15, 0>>
      assert Dispatch.implemented?(0x1FB)

      assert %MsgRandomRoll{minimum: 0, maximum: 1_000_000} =
               Dispatch.to_message(%Packet{opcode: 0x1FB, payload: payload})

      assert_raise FunctionClauseError, fn -> MsgRandomRoll.from_binary(payload <> <<42::little-size(64)>>) end

      assert %MsgRandomRoll{maximum: 0xFFFFFFFF} =
               MsgRandomRoll.from_binary(<<1::little-size(32), 0xFFFFFFFF::little-size(32)>>)
    end
  end

  describe "to_binary/1" do
    test "encodes the shared result and full roller GUID in client order" do
      message = %MsgRandomRollResponse{minimum: 10, maximum: 1000, result: 513, guid: 0x0102030405060708}

      assert MsgRandomRollResponse.to_binary(message) ==
               <<10, 0, 0, 0, 232, 3, 0, 0, 1, 2, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1>>
    end
  end

  describe "handle/2" do
    test "ignores requests before world entry" do
      state = %{ready: false}
      assert Inbound.handle(%MsgRandomRoll{minimum: 1, maximum: 100}, state) == state
      refute_received {:"$gen_cast", {:send_packet, %MsgRandomRollResponse{}}}
    end
  end
end
