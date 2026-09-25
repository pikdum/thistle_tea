defmodule ThistleTea.Game.Player.QuestTurnInTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Battleground.Template
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemProperty
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage
  alias ThistleTea.Game.Network.Message.SmsgItemPushResult
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Battleground.Match
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Battleground, as: BattlegroundLoader
  alias ThistleTea.Game.World.Loader.BroadcastText
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.ItemProperty, as: PropertyLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem
  alias ThistleTea.Game.WorldRef

  @moduletag :vmangos_db

  @required_entry 98_100
  @reward1_entry 98_101
  @reward2_entry 98_102

  setup do
    CharacterStore.init()
    ItemStore.init()
    ItemLoader.init()
    QuestLoader.init()

    id = System.unique_integer([:positive, :monotonic])
    player_guid = Guid.from_low_guid(:player, id)
    npc_entry = 98_200
    npc_guid = Guid.from_low_guid(:mob, npc_entry, id)
    quest_id = 98_300 + rem(id, 10_000)
    Entity.register(npc_guid)

    npc = %{
      object: %Object{guid: npc_guid},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    World.update_position(npc, :mobs)
    Metadata.put(npc_guid, %{alive?: true, npc_flags: 2})

    templates = [
      %ItemTemplate{entry: @required_entry, name: "Required"},
      %ItemTemplate{entry: @reward1_entry, name: "Reward One"},
      %ItemTemplate{entry: @reward2_entry, name: "Reward Two"}
    ]

    Enum.each(templates, &:ets.insert(ItemLoader, {&1.entry, &1}))

    quest = %Quest{
      id: quest_id,
      level: 1,
      required_items: [{0, @required_entry, 2}],
      reward_items: [{@reward1_entry, 1}, {@reward2_entry, 1}]
    }

    :ets.insert(QuestLoader, {{:quest, quest_id}, quest})
    :ets.insert(QuestLoader, {{:ender, npc_entry}, [quest_id]})

    on_exit(fn ->
      Enum.each(templates, &:ets.delete(ItemLoader, &1.entry))
      :ets.delete(QuestLoader, {:quest, quest_id})
      :ets.delete(QuestLoader, {:ender, npc_entry})
      :ets.delete(CharacterStore, id)
      Metadata.delete(player_guid)
      Metadata.delete(npc_guid)
      World.remove_position(npc, :mobs)
      delete_owned_items(player_guid)
    end)

    {:ok, id: id, player_guid: player_guid, npc_guid: npc_guid, quest_id: quest_id}
  end

  test "does not partially grant a collectively oversized reward", context do
    fillers = create_fillers(context.player_guid, 15)
    player = completed_player(context.quest_id, fillers)
    state = state(context, player)

    result = Quests.choose_reward(state, context.npc_guid, context.quest_id, 0)

    assert result == state
    assert QuestLog.active?(result.character.player.quest_log, context.quest_id)
    assert result.character.player.rewarded_quests == MapSet.new()
    assert Inventory.count_entry(result.character.player, @reward1_entry, &ItemStore.get/1) == 0
    assert Inventory.count_entry(result.character.player, @reward2_entry, &ItemStore.get/1) == 0
  end

  test "commits required-item removal and every reward together", context do
    property = %ItemProperty{id: 59_004, suffix: "of Stamina"}

    :ets.insert(PropertyLoader, [
      {{:property, property.id}, property},
      {{:table, @reward1_entry}, [{property.id, 100.0}]}
    ])

    :ets.insert(
      ItemLoader,
      {@reward1_entry, %ItemTemplate{entry: @reward1_entry, name: "Reward One", random_property: @reward1_entry}}
    )

    on_exit(fn ->
      :ets.delete(PropertyLoader, {:property, property.id})
      :ets.delete(PropertyLoader, {:table, @reward1_entry})
    end)

    required1 = ItemStore.create(@required_entry, owner: context.player_guid)
    required2 = ItemStore.create(@required_entry, owner: context.player_guid)
    fillers = create_fillers(context.player_guid, 14)
    player = completed_player(context.quest_id, [required1, required2 | fillers])
    state = state(context, player)

    result = Quests.choose_reward(state, context.npc_guid, context.quest_id, 0)

    refute QuestLog.active?(result.character.player.quest_log, context.quest_id)
    assert MapSet.member?(result.character.player.rewarded_quests, context.quest_id)
    assert Inventory.count_entry(result.character.player, @required_entry, &ItemStore.get/1) == 0
    assert Inventory.count_entry(result.character.player, @reward1_entry, &ItemStore.get/1) == 1
    assert Inventory.count_entry(result.character.player, @reward2_entry, &ItemStore.get/1) == 1
    assert ItemStore.get(required1.object.guid) == nil
    assert ItemStore.get(required2.object.guid) == nil
    assert_receive {:"$gen_cast", {:send_packet, %SmsgItemPushResult{random_property_id: 59_004}}}
  end

  describe "hello/2" do
    test "questgiver-only blacksmiths expose match gossip through the quest hello path", context do
      {world, _pid} = enter_alterac(context.player_guid)
      npc_guid = Guid.from_low_guid(:mob, 13_257, context.id)
      Entity.register(npc_guid)

      npc = %{
        object: %Object{guid: npc_guid},
        internal: %Internal{world: world},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      World.update_position(npc, :mobs)
      Metadata.put(npc_guid, %{alive?: true, npc_flags: 2})
      previous = :ets.lookup(BroadcastText, 9_130)
      :ets.insert(BroadcastText, {9_130, %{text: "How many more supplies are needed?"}})

      on_exit(fn ->
        World.remove_position(npc, :mobs)
        Metadata.delete(npc_guid)
        :ets.delete(BroadcastText, 9_130)
        :ets.insert(BroadcastText, previous)
      end)

      state = state(context, %Player{})
      state = put_in(state.character.internal.world, world)
      result = Quests.hello(state, npc_guid)
      assert result.gossip_menu_guid == npc_guid
      assert [%{action: {:battleground, :armor_status}}] = result.gossip_menu_options

      assert_receive {:"$gen_cast",
                      {:send_packet, %SmsgGossipMessage{guid: ^npc_guid, title_text_id: 6_073, gossips: [_]}}}
    end
  end

  describe "choose_reward/4" do
    test "credits the match only after a successful inventory commit and ignores duplicate reward requests", context do
      quest_id = 6_781
      quest = %{QuestLoader.get(context.quest_id) | id: quest_id}
      previous = :ets.lookup(QuestLoader, {:quest, quest_id})
      :ets.insert(QuestLoader, {{:quest, quest_id}, quest})
      :ets.insert(QuestLoader, {{:ender, Guid.entry(context.npc_guid)}, [quest_id]})
      context = %{context | quest_id: quest_id}
      {world, match_pid} = enter_alterac(context.player_guid)

      on_exit(fn ->
        :ets.delete(QuestLoader, {:quest, quest_id})
        :ets.insert(QuestLoader, previous)
      end)

      npc = %{
        object: %Object{guid: context.npc_guid},
        internal: %Internal{world: world},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      World.update_position(npc, :mobs)
      incomplete = state(context, completed_player(quest_id, []))
      incomplete = put_in(incomplete.character.internal.world, world)
      assert Quests.choose_reward(incomplete, context.npc_guid, quest_id, 0) == incomplete
      assert Match.snapshot(match_pid).armor.alliance.scraps == 0

      required = Enum.map(1..2, fn _ -> ItemStore.create(@required_entry, owner: context.player_guid) end)
      ready = %{incomplete | character: %{incomplete.character | player: completed_player(quest_id, required)}}
      rewarded = Quests.choose_reward(ready, context.npc_guid, quest_id, 0)
      refute QuestLog.active?(rewarded.character.player.quest_log, quest_id)
      assert Inventory.count_entry(rewarded.character.player, @required_entry, &ItemStore.get/1) == 0
      assert BattlegroundSystem.match_for_world(world) == match_pid
      assert Match.snapshot(match_pid).armor.alliance.scraps == 20
      assert Quests.choose_reward(rewarded, context.npc_guid, quest_id, 0) == rewarded
      assert BattlegroundSystem.match_for_world(world) == match_pid
      assert Match.snapshot(match_pid).armor.alliance.scraps == 20
    end
  end

  defp enter_alterac(guid) do
    previous = :ets.lookup(BattlegroundLoader, {:map, 30})

    template = %Template{
      type_id: 1,
      map_id: 30,
      min_players_per_team: 20,
      max_players_per_team: 40,
      min_level: 51,
      max_level: 60,
      alliance_start: {0.0, 0.0, 0.0, 0.0},
      horde_start: {10.0, 0.0, 0.0, 0.0}
    }

    :ets.insert(BattlegroundLoader, {{:map, 30}, template})
    assert :ok = BattlegroundSystem.join(%{guid: guid, name: "Donor", team: :alliance, level: 60}, 30)
    assert {:ok, _status} = BattlegroundSystem.debug_start_queued(guid)
    return_to = {WorldRef.open(0), {0.0, 0.0, 0.0, 0.0}}
    assert {:ok, world, _position} = BattlegroundSystem.port(guid, 1, return_to)
    assert :ok = BattlegroundSystem.debug_start_now(world)
    pid = BattlegroundSystem.match_for_world(world)

    on_exit(fn ->
      BattlegroundSystem.leave(guid, nil)
      :ets.delete(BattlegroundLoader, {:map, 30})
      :ets.insert(BattlegroundLoader, previous)
    end)

    {world, pid}
  end

  defp completed_player(quest_id, items) do
    {:ok, quest_log} = QuestLog.add(%{}, quest_id)
    {:ok, quest_log} = QuestLog.update(quest_log, quest_id, &%{&1 | status: :complete})

    items
    |> Enum.with_index(1)
    |> Enum.reduce(%Player{quest_log: quest_log, coinage: 0}, fn {item, index}, player ->
      struct!(player, [{:"inv#{index}", item.object.guid}])
    end)
  end

  defp state(context, player) do
    character = %Character{
      id: context.id,
      object: %Object{guid: context.player_guid},
      unit: %Unit{race: 1, class: 1, level: 1, health: 100, max_health: 100, auras: []},
      player: player,
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: %WorldRef{map_id: 0}}
    }

    CharacterStore.put(character)
    %{character: character, guid: context.player_guid}
  end

  defp create_fillers(owner, count) do
    Enum.map(1..count, fn offset ->
      template = %ItemTemplate{entry: 99_000 + offset, name: "Filler #{offset}"}
      ItemStore.create(template, owner: owner)
    end)
  end

  defp delete_owned_items(owner) do
    ItemStore
    |> :ets.tab2list()
    |> Enum.each(fn
      {guid, %{item: %{owner: ^owner}}} -> ItemStore.delete(guid)
      _entry -> :ok
    end)
  end
end
