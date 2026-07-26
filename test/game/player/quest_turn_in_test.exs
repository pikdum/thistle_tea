defmodule ThistleTea.Game.Player.QuestTurnInTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata
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
