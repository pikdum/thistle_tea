defmodule ThistleTea.Game.Network.Message.CmsgAutoequipItemSlotTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.CmsgAutoequipItemSlot
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.World.Entity.Player.State

  describe "from_binary/1" do
    test "dispatches the vanilla item GUID and destination slot" do
      guid = 0x4000_0000_0012_3456
      payload = <<guid::little-size(64), 13>>

      assert Dispatch.to_message(Packet.build(payload, 0x10F)) ==
               %CmsgAutoequipItemSlot{item_guid: guid, destination_slot: 13}
    end

    test "rejects incomplete and trailing payloads" do
      for payload <- [<<>>, <<1::little-size(64)>>, <<1::little-size(64), 13, 0>>] do
        assert_raise FunctionClauseError, fn -> CmsgAutoequipItemSlot.from_binary(payload) end
      end
    end
  end

  describe "handle/2" do
    test "ignores requests outside the world" do
      state = %State{}
      assert CmsgAutoequipItemSlot.handle(%CmsgAutoequipItemSlot{item_guid: 1, destination_slot: 0}, state) == state
    end
  end
end
