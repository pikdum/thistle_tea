defmodule ThistleTea.Game.Player.GiftsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Player.Containers
  alias ThistleTea.Game.Player.Gifts
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  @paper 999_921
  @gift 999_922

  setup [:gift]

  describe "CMSG_WRAP_ITEM and CMSG_OPEN_ITEM" do
    test "dispatches wrapping and restores saved gifts with item-value packets instead of loot", context do
      %{state: state, paper: paper, target: target} = context
      assert Dispatch.implemented?(0x1D3)
      message = Dispatch.to_message(%Packet{opcode: 0x1D3, payload: <<255, 23, 255, 24>>})
      assert %Message.CmsgWrapItem{gift_bag: 255, gift_slot: 23, item_bag: 255, item_slot: 24} = message
      wrapped_state = Message.CmsgWrapItem.handle(message, state)
      assert ItemStore.get(paper.object.guid) == nil
      wrapped = ItemStore.get(target.object.guid)
      assert Item.wrapped?(wrapped)
      assert wrapped.object.entry == @gift
      assert wrapped.item.gift_creator == state.guid
      assert CharacterStore.get(state.guid).player.inv1 == 0
      guid = target.object.guid
      assert_receive {:"$gen_cast", {:send_packet, %UpdateObject{object: %{guid: ^guid, entry: @gift}}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: destroyed}}}
      assert destroyed == paper.object.guid
      restored = %{wrapped_state | character: CharacterStore.get(state.guid)}
      opened = Message.CmsgOpenItem.handle(%Message.CmsgOpenItem{bag: 255, slot: 24}, restored)
      assert ItemStore.get(target.object.guid) == target
      assert opened.loot_guid == nil
      assert opened.loot_type == nil
      assert CharacterStore.get(state.guid).player.inv2 == target.object.guid
      assert_receive {:"$gen_cast", {:send_packet, %UpdateObject{object: %{guid: ^guid, entry: 25}}}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgLootResponse{}}}
      assert Containers.open(opened, {255, 24}) == opened
      assert ItemStore.get(target.object.guid) == target
    end

    test "rejects bank access, remote control, death and invalid paper without consuming items", context do
      %{state: state, paper: paper, target: target} = context

      banked = %{
        state
        | character: %{state.character | player: %{state.character.player | inv2: 0, bank1: target.object.guid}}
      }

      assert Gifts.wrap(banked, {255, 23}, {255, 39}).character == banked.character
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: 35}}}
      controlled = %{state | active_mover_guid: state.guid + 1}
      assert Gifts.wrap(controlled, {255, 23}, {255, 24}) == controlled
      dead = %{state | character: %{state.character | unit: %{state.character.unit | health: 0}}}
      assert Gifts.wrap(dead, {255, 23}, {255, 24}) == dead
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInventoryChangeFailure{code: 38}}}
      paper = %{paper | internal: %{paper.internal | template: %{Item.template(paper) | wrapped_gift: 0}}}
      ItemStore.put(paper)
      assert Gifts.wrap(state, {255, 23}, {255, 24}) == state
      assert ItemStore.get(paper.object.guid) == paper
      assert ItemStore.get(target.object.guid) == target
    end

    test "settles a completed cast's charge before wrapping its item", %{state: state, target: target} do
      template = %{Item.template(target) | spellid_1: 1, spellcharges_1: -5}
      target = %{target | internal: %{target.internal | template: template}}
      target = target |> Item.put_spell_charge(1, -3) |> ItemStore.put()
      send(self(), {:consume_cast_item, target.object.guid})
      wrapped = Gifts.wrap(state, {255, 23}, {255, 24})
      item = ItemStore.get(target.object.guid)
      assert Item.wrapped?(item)
      assert Item.spell_charge(item, 1) == -2
      Containers.open(wrapped, {255, 24})
      assert Item.spell_charge(ItemStore.get(target.object.guid), 1) == -2
    end
  end

  defp gift(_context) do
    owner = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
    paper = ItemStore.create(%ItemTemplate{entry: @paper, flags: 512, stackable: 10, wrapped_gift: @gift}, owner: owner)
    target = ItemStore.create(%ItemTemplate{entry: 25, class: 2, max_durability: 20}, owner: owner)
    target = ItemStore.put(%{target | item: %{target.item | gift_creator: 0}})
    :ets.insert(ItemLoader, {@gift, %ItemTemplate{entry: @gift, flags: 512}})

    character = %Character{
      id: owner,
      object: %Object{guid: owner},
      unit: %Unit{health: 100, level: 20, race: 1, class: 1},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{},
      player: %Player{inv1: paper.object.guid, inv2: target.object.guid, coinage: 100}
    }

    CharacterStore.put(character)

    on_exit(fn ->
      :ets.delete(ItemLoader, @gift)
      :ets.delete(CharacterStore, owner)
      ItemStore.delete(paper.object.guid)
      ItemStore.delete(target.object.guid)
    end)

    %{state: %State{ready: true, guid: owner, character: character}, paper: paper, target: target}
  end
end
