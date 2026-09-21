defmodule ThistleTea.Game.Network.Message.TradeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Spell.TargetCodec

  describe "trade packets" do
    test "parses the seventh trade slot as a slot rather than an item GUID" do
      target = %Target{selection: {:trade_item, 6}}
      assert TargetCodec.encode(target) == <<0x1000::little-16, 1, 6>>
      assert TargetCodec.parse(<<0x1000::little-16, 1, 6>>, 123) == target
      assert Target.item_guid(target) == nil
    end

    test "dispatches every vanilla client trade opcode" do
      packets = [
        {0x116, <<123::little-64>>, %Message.CmsgInitiateTrade{player_guid: 123}},
        {0x117, <<>>, %Message.CmsgBeginTrade{}},
        {0x118, <<>>, %Message.CmsgBusyTrade{}},
        {0x119, <<>>, %Message.CmsgIgnoreTrade{}},
        {0x11A, <<1::little-32>>, %Message.CmsgAcceptTrade{unknown: 1}},
        {0x11B, <<>>, %Message.CmsgUnacceptTrade{}},
        {0x11C, <<>>, %Message.CmsgCancelTrade{}},
        {0x11D, <<6, 255, 23>>, %Message.CmsgSetTradeItem{trade_slot: 6, bag: 255, slot: 23}},
        {0x11E, <<6>>, %Message.CmsgClearTradeItem{trade_slot: 6}},
        {0x11F, <<12_345::little-32>>, %Message.CmsgSetTradeGold{gold: 12_345}}
      ]

      Enum.each(packets, fn {opcode, body, expected} ->
        assert Dispatch.to_message(Packet.build(body, opcode)) == expected
      end)
    end

    test "encodes status-specific data" do
      assert Message.SmsgTradeStatus.to_binary(%Message.SmsgTradeStatus{status: :begin_trade, player_guid: 123}) ==
               <<1::little-32, 123::little-64>>

      assert Message.SmsgTradeStatus.to_binary(%Message.SmsgTradeStatus{status: :trade_complete}) == <<8::little-32>>

      assert Message.SmsgTradeStatus.to_binary(%Message.SmsgTradeStatus{
               status: :close_window,
               inventory_result: 50,
               target_error: true
             }) == <<12::little-32, 50::little-32, 1, 0::little-32>>
    end

    test "encodes all seven slots with item identity and enchantment fields" do
      item = Item.build(%ItemTemplate{entry: 25, display_id: 1542, max_durability: 20}, 101, owner: 1)
      item = Item.put_permanent_enchantment(item, 1897)
      item = %{item | item: %{item.item | creator: 99, spell_charges: 3, durability: 12}}

      binary =
        Message.SmsgTradeStatusExtended.to_binary(%Message.SmsgTradeStatusExtended{
          other?: true,
          money: 123,
          spell_id: 7418,
          items: %{6 => item}
        })

      assert <<1, 7::little-32, 7::little-32, 123::little-32, 7418::little-32, slots::binary>> = binary
      assert byte_size(slots) == 7 * 61
      assert <<0, 0::size(480), _::binary>> = slots

      assert <<6, 25::little-32, 1542::little-32, 1::little-32, 0::little-32, 0::little-64, 1897::little-32,
               99::little-64, 3::little-32, 0::little-32, 0::little-32, 0::little-32, 20::little-32, 12::little-32>> =
               binary_part(slots, 6 * 61, 61)
    end

    test "projects a wrapped gift's visible identity and creator" do
      item = Item.build(%ItemTemplate{entry: 25}, 101, owner: 1)
      gift = Item.wrap(item, %ItemTemplate{entry: 5043, flags: 512, display_id: 8000}, 1)
      binary = Message.SmsgTradeStatusExtended.to_binary(%Message.SmsgTradeStatusExtended{items: %{0 => gift}})

      assert <<_header::binary-size(17), 0, 5043::little-32, 8000::little-32, 1::little-32, 1::little-32, 1::little-64,
               _rest::binary>> = binary
    end
  end
end
