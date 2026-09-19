defmodule ThistleTea.Game.Player.DisenchantTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Disenchant
  alias ThistleTea.Game.Player.ItemLoot
  alias ThistleTea.Game.Player.Looting
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader

  @material 987_901
  @loot 987_902

  setup [:inventory]

  describe "complete/3" do
    test "consumes only the selected instance, rolls private loot, and advances skill once", %{
      state: state,
      first: first,
      selected: selected
    } do
      completed = Disenchant.complete(state, selected.object.guid, 13_262)
      assert completed.character.player.inv1 == first.object.guid
      assert ItemStore.get(first.object.guid) == first
      assert ItemStore.get(selected.object.guid) == nil
      assert completed.character.player.skills[333].value == 2
      assert completed.loot_guid == selected.object.guid
      assert completed.loot_type == :item
      assert completed.character.internal.item_loot.source == selected
      assert [%{item_id: @material, count: 2}] = completed.character.internal.item_loot.loot.items
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgLootResponse{loot_type: 2}}}

      assert Disenchant.complete(completed, selected.object.guid, 13_262) == completed
      assert ItemStore.get(first.object.guid) == first
      assert CharacterStore.get(state.guid).internal.item_loot == completed.character.internal.item_loot
    end

    test "rejects a sold or transferred target at completion", %{state: state, selected: selected} do
      state = %{state | character: %{state.character | player: %{state.character.player | inv2: 0}}}
      assert Disenchant.complete(state, selected.object.guid, 13_262) == state
      assert ItemStore.get(selected.object.guid) == selected
    end

    test "rejects a dead caster and empty loot without consuming the item", %{state: state, selected: selected} do
      dead = %{state | character: %{state.character | unit: %{state.character.unit | health: 0}}}
      assert Disenchant.complete(dead, selected.object.guid, 13_262) == dead
      :ets.delete(LootLoader, {:disenchant, @loot})
      assert Disenchant.complete(state, selected.object.guid, 13_262) == state
      assert ItemStore.get(selected.object.guid) == selected
    end
  end

  describe "take_item/2" do
    test "claims once through inventory updates and clears pending loot", %{state: state, selected: selected} do
      opened = Disenchant.complete(state, selected.object.guid, 13_262)
      source_guid = selected.object.guid
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^source_guid}}}
      claimed = Looting.take_item(opened, 0)
      assert count(claimed, @material) == 2
      assert claimed.character.internal.item_loot == nil
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^source_guid}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgLootRemoved{slot: 0}}}
      assert Looting.take_item(claimed, 0) == claimed
      assert CharacterStore.get(state.guid).internal.item_loot == nil
    end

    test "retains a failed claim and recovers after making room", %{state: state, selected: selected} do
      opened = Disenchant.complete(state, selected.object.guid, 13_262)
      full = fill_bags(opened)
      pending = full.character.internal.item_loot
      assert Looting.take_item(full, 0) == full
      assert count(full, @material) == 0

      closed = Looting.release(full)
      assert closed.loot_guid == nil
      assert closed.character.internal.item_loot == pending
      restored = %{closed | character: CharacterStore.get(state.guid)} |> ItemLoot.open()
      assert restored.loot_guid == selected.object.guid
      freed = %{restored | character: %{restored.character | player: %{restored.character.player | inv16: 0}}}
      claimed = Looting.take_item(freed, 0)
      assert count(claimed, @material) == 2
      assert claimed.character.internal.item_loot == nil
    end

    test "does not allow a dead player or another loot window to claim", %{state: state, selected: selected} do
      opened = Disenchant.complete(state, selected.object.guid, 13_262)
      dead = %{opened | character: %{opened.character | unit: %{opened.character.unit | health: 0}}}
      assert ItemLoot.take_item(dead, 0) == dead
      foreign = %{opened | loot_guid: selected.object.guid + 1}
      assert ItemLoot.take_item(foreign, 0) == foreign
    end
  end

  describe "release/1" do
    test "automatically stores remaining materials and never grants them again", %{state: state, selected: selected} do
      closed = state |> Disenchant.complete(selected.object.guid, 13_262) |> Looting.release()
      assert count(closed, @material) == 2
      assert closed.character.internal.item_loot == nil
      assert closed.loot_guid == nil
      assert Looting.release(closed) == closed
    end
  end

  defp count(state, entry), do: Inventory.count_entry(state.character.player, entry, &ItemStore.get/1)

  defp fill_bags(state) do
    player =
      Enum.reduce(2..16, state.character.player, fn slot, player ->
        item = ItemStore.create(%ItemTemplate{entry: 987_903}, owner: state.guid)
        Map.replace!(player, :"inv#{slot}", item.object.guid)
      end)

    character = %{state.character | player: player}
    CharacterStore.put(character)
    %{state | character: character}
  end

  defp inventory(_context) do
    ItemStore.init()
    ItemLoader.init()
    LootLoader.init()
    low = System.unique_integer([:positive, :monotonic])
    guid = Guid.from_low_guid(:player, low)
    template = %ItemTemplate{entry: 987_900, disenchant_id: @loot}
    first = ItemStore.create(template, owner: guid)
    selected = ItemStore.create(template, owner: guid)
    :ets.insert(ItemLoader, {@material, %ItemTemplate{entry: @material, stackable: 20}})

    :ets.insert(
      LootLoader,
      {{:disenchant, @loot}, [%{item: @material, chance: 100.0, groupid: 0, mincount_or_ref: 2, maxcount: 2}]}
    )

    character = %Character{
      id: low,
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, level: 10},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      player: %Player{
        inv1: first.object.guid,
        inv2: selected.object.guid,
        skills: %{333 => %{value: 1, max: 75, range: :tier}}
      },
      internal: %Internal{}
    }

    CharacterStore.put(character)

    on_exit(fn ->
      :ets.delete(CharacterStore, low)
      :ets.delete(ItemLoader, @material)
      :ets.delete(LootLoader, {:disenchant, @loot})

      :ets.select_delete(ItemStore, [{{:_, :"$1"}, [{:==, {:map_get, :owner, {:map_get, :item, :"$1"}}, guid}], [true]}])
    end)

    %{state: %State{guid: guid, character: character}, first: first, selected: selected}
  end
end
