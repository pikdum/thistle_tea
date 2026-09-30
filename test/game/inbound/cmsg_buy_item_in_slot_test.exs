defmodule ThistleTea.Game.Inbound.CmsgBuyItemInSlotTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Inbound
  alias ThistleTea.Game.Inbound.CmsgBuyItemInSlot
  alias ThistleTea.Game.Inbound.Dispatch
  alias ThistleTea.Game.Network.Packet

  describe "from_binary/1" do
    test "dispatches the build-5875 vendor, item, bag, slot and bundle count" do
      payload = <<0xF130000123000001::little-size(64), 159::little-size(32), 0x4000000000000020::little-size(64), 5, 3>>
      assert Dispatch.implemented?(0x01A3)

      assert %CmsgBuyItemInSlot{
               vendor_guid: 0xF130000123000001,
               item_id: 159,
               bag_guid: 0x4000000000000020,
               slot: 5,
               count: 3
             } = Dispatch.to_message(%Packet{opcode: 0x01A3, payload: payload})
    end
  end

  describe "handle/2" do
    test "ignores purchases before world entry" do
      assert Inbound.handle(%CmsgBuyItemInSlot{}, %{ready: false}) == %{ready: false}
    end
  end
end
