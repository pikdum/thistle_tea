defmodule ThistleTea.Game.Inbound.CmsgGmticketCreateTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Inbound
  alias ThistleTea.Game.Inbound.CmsgGmticketCreate
  alias ThistleTea.Game.Inbound.Dispatch
  alias ThistleTea.Game.Network.Message.SmsgGmticketCreate
  alias ThistleTea.Game.Network.Message.SmsgGmticketDeleteticket
  alias ThistleTea.Game.Network.Message.SmsgGmticketGetticket
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.Tickets
  alias ThistleTea.Test.Unique

  describe "from_binary/1" do
    test "reads the category, position, and text" do
      payload = <<1, 0::little-32, 1.5::little-float-32, 2.5::little-float-32, 3.5::little-float-32, "Help me", 0, 0>>

      assert %CmsgGmticketCreate{type: 1, map_id: 0, position: {1.5, 2.5, 3.5}, message: "Help me"} =
               Dispatch.to_message(%Packet{opcode: Opcodes.get(:CMSG_GMTICKET_CREATE), payload: payload})
    end
  end

  describe "handle/2" do
    test "files a ticket the help frame then shows, and abandons it" do
      guid = Unique.integer()
      {:ok, _} = Entity.register(guid)
      on_exit(fn -> Entity.unregister(guid) end)
      state = %{ready: true, guid: guid, character: %{internal: %{name: "Tester"}}}

      Inbound.handle(%CmsgGmticketCreate{type: 4, map_id: 0, position: {0.0, 0.0, 0.0}, message: "Lost item"}, state)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgGmticketCreate{response: 2}}}

      Inbound.handle(%CmsgGmticketCreate{type: 4, map_id: 0, position: {0.0, 0.0, 0.0}, message: "Again"}, state)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgGmticketCreate{response: 3}}}

      Tickets.show(state)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgGmticketGetticket{message: "Lost item", type: 4}}}

      Tickets.abandon(state)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgGmticketDeleteticket{response: 9}}}
      assert_receive {:"$gen_cast", {:send_packet, %SmsgGmticketGetticket{message: nil}}}
    end
  end

  describe "SmsgGmticketGetticket.to_binary/1" do
    test "sends a bare default status without a ticket" do
      assert SmsgGmticketGetticket.to_binary(%SmsgGmticketGetticket{}) == <<0x0A::little-32>>

      assert <<0x06::little-32, "Hi", 0, 3, _ages::binary-size(12), 0, 1>> =
               SmsgGmticketGetticket.to_binary(%SmsgGmticketGetticket{message: "Hi", type: 3, opened_by_gm: 1})
    end
  end
end
