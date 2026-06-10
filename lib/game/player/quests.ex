defmodule ThistleTea.Game.Player.Quests do
  alias ThistleTea.Character
  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.QuestDialogStatus
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestLog.Entry
  alias ThistleTea.Game.Entity.Logic.QuestRequirements
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader

  def ctx(%Character{} = character) do
    %{
      level: character.unit.level,
      race: character.unit.race,
      class: character.unit.class,
      quest_log: character.player.quest_log,
      rewarded_quests: character.player.rewarded_quests || MapSet.new()
    }
  end

  def dialog_status(npc_guid, %Character{} = character) do
    {giver_quests, ender_quests} = npc_quests(npc_guid)
    QuestDialogStatus.for_npc(giver_quests, ender_quests, ctx(character))
  end

  def hello(state, npc_guid) do
    {giver_quests, ender_quests} = npc_quests(npc_guid)

    case QuestDialogStatus.menu(giver_quests, ender_quests, ctx(state.character)) do
      [] ->
        state

      [{%Quest{} = quest, icon}] ->
        if icon == QuestDialogStatus.available() do
          send_details(npc_guid, quest)
        else
          send_quest_list(npc_guid, [{quest, icon}])
        end

        state

      entries ->
        send_quest_list(npc_guid, entries)
        state
    end
  end

  def query_quest(state, npc_guid, quest_id) do
    entry = Guid.entry(npc_guid)

    with %Quest{} = quest <- QuestLoader.get(quest_id),
         true <-
           quest_id in QuestLoader.given_by(entry) or quest_id in QuestLoader.ended_by(entry) do
      send_details(npc_guid, quest)
    end

    state
  end

  def accept(state, npc_guid, quest_id) do
    if quest_id in QuestLoader.given_by(Guid.entry(npc_guid)) do
      force_accept(state, quest_id)
    else
      state
    end
  end

  def force_accept(%{character: %Character{player: player} = character} = state, quest_id) do
    with %Quest{} = quest <- QuestLoader.get(quest_id),
         :ok <- QuestRequirements.can_take(quest, ctx(character)),
         {:ok, quest_log} <- QuestLog.add(player.quest_log, quest_id),
         {:ok, state} <- grant_source_item(state, quest) do
      quest_log = maybe_autocomplete(quest_log, quest)
      character = state.character
      character = %{character | player: %{character.player | quest_log: quest_log}}
      put_character(state, character)
    else
      {:error, :log_full} ->
        Network.send_packet(%Message.SmsgQuestlogFull{})
        state

      {:error, :inventory_full} ->
        InventoryUpdate.send_failure(:inventory_full, 0, 0)
        state

      _other ->
        state
    end
  end

  def abandon(%{character: %Character{player: player} = character} = state, slot) do
    case Map.get(player.quest_log || %{}, slot) do
      %Entry{quest_id: quest_id} ->
        {:ok, quest_log} = QuestLog.remove(player.quest_log, quest_id)
        put_character(state, %{character | player: %{player | quest_log: quest_log}})

      _entry ->
        state
    end
  end

  def npc_quests(npc_guid) do
    entry = Guid.entry(npc_guid)
    {load_quests(QuestLoader.given_by(entry)), load_quests(QuestLoader.ended_by(entry))}
  end

  def send_details(npc_guid, %Quest{} = quest) do
    Network.send_packet(%Message.SmsgQuestgiverQuestDetails{
      npc_guid: npc_guid,
      quest: quest,
      activate_accept: true
    })
  end

  defp send_quest_list(npc_guid, entries) do
    Network.send_packet(%Message.SmsgQuestgiverQuestList{
      npc_guid: npc_guid,
      title: "",
      entries: entries
    })
  end

  defp maybe_autocomplete(quest_log, %Quest{required_kills: [], required_items: []} = quest) do
    case QuestLog.update(quest_log, quest.id, fn entry -> %{entry | status: :complete} end) do
      {:ok, quest_log} -> quest_log
      _error -> quest_log
    end
  end

  defp maybe_autocomplete(quest_log, %Quest{}), do: quest_log

  defp grant_source_item(state, %Quest{src_item_id: src_item_id}) when src_item_id <= 0, do: {:ok, state}

  defp grant_source_item(%{guid: guid} = state, %Quest{src_item_id: src_item_id} = quest) do
    count = max(quest.src_item_count, 1)

    case ItemStore.create(src_item_id, owner: guid, stack_count: count) do
      %DataItem{} = item ->
        case Inventory.store(state.character.player, guid, item, &ItemStore.get/1) do
          {:ok, result, placement} ->
            state = InventoryUpdate.apply(state, {:ok, result})
            send_item_push(state, item, placement, count)
            {:ok, state}

          _error ->
            ItemStore.delete(item.object.guid)
            {:error, :inventory_full}
        end

      _error ->
        {:ok, state}
    end
  end

  defp send_item_push(state, item, placement, count) do
    {bag_slot, item_slot} =
      case placement do
        {:placed, {bag, slot}, placed} ->
          ItemStore.put(placed)
          Network.send_packet(UpdateObject.from_item(placed))
          {bag, slot}

        :merged ->
          ItemStore.delete(item.object.guid)
          {Inventory.bag_0(), 0xFFFFFFFF}
      end

    Network.send_packet(%Message.SmsgItemPushResult{
      player_guid: state.guid,
      item_id: item.object.entry,
      bag_slot: bag_slot,
      item_slot: item_slot,
      count: count,
      created: 1
    })
  end

  defp load_quests(quest_ids) do
    quest_ids
    |> Enum.map(&QuestLoader.get/1)
    |> Enum.reject(&is_nil/1)
  end

  defp put_character(state, %Character{} = character) do
    Character.save(character)

    update = Core.update_object(character, :values)
    Network.send_packet(update)
    World.broadcast_packet(update, character, include_self?: false)

    %{state | character: character}
  end
end
