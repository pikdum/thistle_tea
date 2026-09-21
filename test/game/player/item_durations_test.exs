defmodule ThistleTea.Game.Player.ItemDurationsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.ItemLifetime
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.DevCommands
  alias ThistleTea.Game.Player.ItemDurations
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata

  @entry 999_940

  setup [:timed_inventory]

  describe "sync/2 and tick/3" do
    test "removing a timed quest item makes it needed again", %{state: state, item: item} do
      quest = %Quest{id: 999_942, required_items: [{0, @entry, 1}]}
      :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
      on_exit(fn -> :ets.delete(QuestLoader, {:quest, quest.id}) end)
      {:ok, log} = QuestLog.add(%{}, quest.id)
      character = %{state.character | player: %{state.character.player | quest_log: log}}
      assert Quests.needed_items(character) == MapSet.new()
      item |> ItemLifetime.set_remaining(1, Time.now() - 2_000) |> ItemStore.put()
      done = ItemDurations.expire_due(%{state | character: character})
      assert Quests.needed_items(done.character) == MapSet.new([@entry])
      assert %{needed_quest_items: needed} = Metadata.query(state.guid, [:needed_quest_items])
      assert needed == MapSet.new([@entry])
    end

    test "publishes remaining seconds without renewing a deadline or replacing its timer", %{state: state, item: item} do
      now = Time.now()
      state = ItemDurations.sync(state, now)
      guid = item.object.guid
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemTimeUpdate{guid: ^guid, duration: 300}}}
      same = ItemDurations.sync(state, now + 100_001)
      assert same.item_duration_timer == state.item_duration_timer
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgItemTimeUpdate{guid: ^guid, duration: 200}}}
      assert ItemLifetime.deadline(ItemStore.get(guid)) == now + 300_000
      assert ItemDurations.tick(same, make_ref(), now + 300_000) == same
      done = ItemDurations.tick(same, state.item_duration_timer.token, now + 300_000)
      assert done.character.player.inv1 == 0
      assert done.item_duration_timer == nil
      assert ItemStore.get(guid) == nil
      assert CharacterStore.get(state.guid).player.inv1 == 0
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^guid}}}
      assert ItemDurations.tick(done, state.item_duration_timer.token, now + 400_000) == done
    end

    test "the old owner's timer cannot remove a transferred item", %{state: state, item: item} do
      now = Time.now()
      state = ItemDurations.sync(state, now)
      item = ItemStore.get(item.object.guid)
      recipient = state.guid + 1
      ItemStore.put(%{item | item: %{item.item | owner: recipient, contained: recipient}})
      done = ItemDurations.tick(state, state.item_duration_timer.token, now + 300_000)
      assert ItemStore.get(item.object.guid).item.owner == recipient
      assert done.item_duration_timer == nil
    end

    test "the owner callback expires equipment and recomputes its bonuses", %{state: state, item: item} do
      player = Inventory.equip(%{state.character.player | inv1: 0}, :mainhand, item)
      character = Character.sync_equipment_stats(%{state.character | player: player})
      assert character.unit.base_min_damage == 30
      assert character.unit.max_health == 150
      item |> ItemLifetime.set_remaining(1, Time.now() - 2_000) |> ItemStore.put()
      state = ItemDurations.sync(%{state | character: character})

      assert {:noreply, done, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_info({:item_duration_tick, state.item_duration_timer.token}, state)

      assert done.character.player.mainhand == 0
      assert done.character.unit.base_min_damage == 1.0
      assert done.character.unit.max_health == 100
      assert done.character.player.visible_item_16_0 == 0
      assert ItemStore.get(item.object.guid) == nil
    end

    test "expiration cancels a cast using the removed item", %{state: state, item: item} do
      cast = %Cast{spell: %Spell{id: 999_941}, cast_item_guid: item.object.guid}
      character = %{state.character | internal: %{state.character.internal | casting: cast}}
      item |> ItemLifetime.set_remaining(1, Time.now() - 2_000) |> ItemStore.put()
      done = ItemDurations.expire_due(%{state | character: character})
      assert done.character.internal.casting == nil
      assert ItemStore.get(item.object.guid) == nil
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{spell: 999_941}}}
    end

    test "expiration closes a container loot window without retaining the source", %{state: state, item: item} do
      item |> ItemLifetime.set_remaining(1, Time.now() - 2_000) |> ItemStore.put()
      done = ItemDurations.expire_due(%{state | loot_guid: item.object.guid, loot_type: :container})
      assert done.loot_guid == nil
      assert done.loot_type == nil
      assert ItemStore.get(item.object.guid) == nil
      guid = item.object.guid
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgLootReleaseResponse{guid: ^guid}}}
    end
  end

  describe "logout/2 and restore/2" do
    test "ordinary items resume their exact saved budget and ignore stale owner messages", %{state: state, item: item} do
      now = Time.now()
      state = ItemDurations.sync(state, now)
      token = state.item_duration_timer.token
      logged_out = ItemDurations.logout(state, now + 11_001)
      assert logged_out.item_duration_timer == nil
      refute logged_out.item_durations_active?
      assert ItemLifetime.remaining_ms(ItemStore.get(item.object.guid), now + 1_000_000) == 288_999
      assert ItemDurations.tick(logged_out, token, now + 1_000_000) == logged_out
      restored = ItemDurations.restore(logged_out.character, now + 1_000_000)
      assert restored.internal.item_logout_at == nil
      assert ItemLifetime.deadline(ItemStore.get(item.object.guid)) == now + 1_288_999
    end

    test "real-time expiry and conjured bank cleanup occur before login publication", %{state: state, item: item} do
      now = Time.now()
      item = %{item | internal: %{item.internal | template: %{Item.template(item) | flags: 0x10002}}}
      item |> ItemLifetime.start(now) |> ItemStore.put()
      character = %{state.character | internal: %{state.character.internal | item_logout_at: now}}
      restored = ItemDurations.restore(character, now + 300_000)
      assert restored.player.inv1 == 0
      assert ItemStore.get(item.object.guid) == nil
      conjured = %{item | item: %{item.item | duration: 0}, internal: Map.delete(item.internal, :duration)}
      ItemStore.put(conjured)
      character = %{character | player: %{character.player | inv1: 0, bank1: item.object.guid}}
      assert ItemDurations.restore(character, now + 900_000).player.bank1 == item.object.guid
      assert ItemDurations.restore(character, now + 900_001).player.bank1 == 0
      assert ItemStore.get(item.object.guid) == nil
    end
  end

  describe "inventory publication" do
    test "a newly granted item starts once and debug changes use the same timer", %{state: state, item: item} do
      state = %{state | character: %{state.character | player: %Player{}}}
      changes = state.character.player |> Batch.new() |> Batch.add(item) |> Inventory.plan(&ItemStore.get/1)
      state = InventoryUpdate.apply(state, changes)
      assert is_integer(ItemLifetime.deadline(ItemStore.get(item.object.guid)))
      assert {:handled, shortened} = DevCommands.run(state, ".debug item duration  999940  20 ")
      assert ItemLifetime.remaining_ms(ItemStore.get(item.object.guid), Time.now()) in 19_000..20_000
      assert shortened.item_duration_timer.deadline < state.item_duration_timer.deadline
      assert {:handled, ^shortened} = DevCommands.run(shortened, ".debug item duration 999940 0")
      assert {:handled, ^shortened} = DevCommands.run(shortened, ".debug item duration 999940 604801")
      ItemDurations.logout(shortened)
    end

    test "encodes the vanilla item timer packet" do
      packet = %Message.SmsgItemTimeUpdate{guid: 0x4000000000000001, duration: 300}
      assert Message.SmsgItemTimeUpdate.to_binary(packet) == <<1, 0, 0, 0, 0, 0, 0, 64, 44, 1, 0, 0>>
    end
  end

  defp timed_inventory(_context) do
    owner = System.unique_integer([:positive, :monotonic])

    template = %ItemTemplate{
      entry: @entry,
      duration: 300,
      class: 2,
      inventory_type: 13,
      dmg_min1: 30,
      dmg_max1: 40,
      stat_type1: 1,
      stat_value1: 50
    }

    :ets.insert(ItemLoader, {@entry, template})
    item = ItemStore.create(template, owner: owner)

    character = %Character{
      id: owner,
      object: %Object{guid: owner},
      player: %Player{inv1: item.object.guid},
      unit: %Unit{health: 100, max_health: 100, base_health: 100, level: 50, race: 1, class: 1},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    CharacterStore.put(character)

    on_exit(fn ->
      ItemStore.delete(item.object.guid)
      :ets.delete(ItemLoader, @entry)
      :ets.delete(CharacterStore, owner)
      Metadata.delete(owner)
    end)

    %{state: %State{guid: owner, ready: true, character: character, item_durations_active?: true}, item: item}
  end
end
