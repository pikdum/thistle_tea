defmodule ThistleTea.Game.World.Entity.Player.ItemLocationLimitsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.DBC
  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Inventory.Batch
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.Equipment
  alias ThistleTea.Game.World.Entity.Player.InventoryUpdate
  alias ThistleTea.Game.World.Entity.Player.ItemLocationLimits
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Exploration, as: ExplorationLoader
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Test.Unique

  setup [:owned_item]

  describe "reconcile/2" do
    test "an authoritative zone change revalidates a cached player", context do
      cached = ItemLocationLimits.reconcile(context.state, zone_id: context.zone)
      assert cached.character.player.inv1 == context.item.object.guid
      changed = ItemLocationLimits.reconcile(cached, zone_id: context.outside)
      assert changed.character.player.inv1 == 0
    end

    test "removing equipped gear recomputes its stats and visible fields", context do
      template = %{Item.template(context.item) | inventory_type: 13, class: 2, stat_type1: 1, stat_value1: 50}
      :ets.insert(ItemLoader, {template.entry, template})
      on_exit(fn -> :ets.delete(ItemLoader, template.entry) end)
      item = %{context.item | internal: Map.put(context.item.internal, :template, template)}
      ItemStore.put(item)
      character = context.state.character
      player = %{character.player | inv1: 0} |> Inventory.equip(:mainhand, item)
      character = Equipment.sync_stats(%{character | player: player})
      assert character.unit.max_health == 150
      state = ItemLocationLimits.reconcile(%{context.state | character: character}, zone_id: context.outside)
      assert state.character.player.mainhand == 0
      assert state.character.player.visible_item_16_0 == 0
      assert state.character.unit.max_health == 100
    end

    test "removal cancels an item cast, closes its loot window and projects destruction", context do
      spell_id = Unique.integer()
      cast = %Cast{spell: %Spell{id: spell_id}, cast_item_guid: context.item.object.guid}
      character = %{context.state.character | internal: %{context.state.character.internal | casting: cast}}
      state = %{context.state | character: character, loot_guid: context.item.object.guid, loot_type: :container}
      done = ItemLocationLimits.reconcile(state, zone_id: Unique.integer())
      assert done.character.internal.casting == nil
      assert done.character.player.inv1 == 0
      assert done.loot_guid == nil
      assert ItemStore.get(context.item.object.guid) == nil
      assert ItemLocationLimits.reconcile(done) == done
      guid = context.item.object.guid
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^guid}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgLootReleaseResponse{guid: ^guid}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{spell: ^spell_id}}}
    end

    test "the owner publication funnel preserves ghosts and rechecks resurrection", context do
      character = context.state.character
      outside = %{character | internal: %{character.internal | area: context.outside}}
      ghost = %{outside | player: %{outside.player | flags: 0x10}, unit: %{outside.unit | health: 1}}
      state = PlayerServer.maybe_broadcast_update(%{context.state | character: ghost})
      assert state.character.player.inv1 == context.item.object.guid
      {resurrected, _events} = Death.resurrect(state.character, 1.0, Time.now())
      done = PlayerServer.maybe_broadcast_update(%{state | character: resurrected})
      assert done.character.player.inv1 == 0
      assert ItemStore.get(context.item.object.guid) == nil
    end

    test "inventory publication invalidates a cached scope even when player fields stay equal", context do
      state = ItemLocationLimits.reconcile(context.state, zone_id: context.zone)
      template = %{Item.template(context.item) | area: context.outside}
      changed = %{context.item | internal: Map.put(context.item.internal, :template, template)}
      batch = Batch.update(Batch.new(state.character.player), changed)
      published = InventoryUpdate.apply(state, Inventory.plan(batch, &ItemStore.get/1))
      assert published.character.player == state.character.player
      assert published.item_location_snapshot == nil
      assert ItemLocationLimits.reconcile(published, zone_id: context.zone).character.player.inv1 == 0
    end

    test "an unknown terrain hint uses the cached authoritative parent zone", context do
      assert ItemLocationLimits.reconcile(context.state, zone_id: nil).character.player.inv1 == context.item.object.guid
    end
  end

  describe "restore/2" do
    test "login commits removal of a banked item before inventory is sent", context do
      character = context.state.character
      character = %{character | player: %Player{bank1: context.item.object.guid}}
      done = ItemLocationLimits.restore(character, zone_id: context.outside)
      assert done.player.bank1 == 0
      assert ItemStore.get(context.item.object.guid) == nil
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{}}}
    end
  end

  defp owned_item(_context) do
    owner = Unique.integer()
    map = Unique.integer()
    zone = Unique.integer()
    outside = Unique.integer()
    area = Unique.integer()
    template = %ItemTemplate{entry: Unique.integer(), area: zone}
    item = Item.build(template, Guid.from_low_guid(:item, Unique.integer()), owner: owner)
    ItemStore.put(item)
    :ets.insert(ExplorationLoader, {{:area, area}, %DBC.AreaTable{id: area, map: map, parent_area_table: zone}})
    :ets.insert(ExplorationLoader, {{:area, outside}, %DBC.AreaTable{id: outside, map: map, parent_area_table: 0}})

    character = %Character{
      id: owner,
      object: %Object{guid: owner},
      player: %Player{inv1: item.object.guid, broken_equipment: []},
      unit: %Unit{health: 100, max_health: 100, base_health: 100, level: 20, race: 1, class: 1, auras: []},
      internal: %Internal{world: WorldRef.open(map), area: area},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    character = InventoryUpdate.sync_character(character, character.player)

    on_exit(fn ->
      ItemStore.delete(item.object.guid)
      :ets.delete(CharacterStore, owner)
      :ets.delete(ExplorationLoader, {:area, area})
      :ets.delete(ExplorationLoader, {:area, outside})
      Metadata.delete(owner)
    end)

    %{state: %State{guid: owner, ready: true, character: character}, item: item, zone: zone, outside: outside}
  end
end
