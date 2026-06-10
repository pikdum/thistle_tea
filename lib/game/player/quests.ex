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
    with %Quest{} = quest <- QuestLoader.get(quest_id),
         true <- quest_id in QuestLoader.given_by(Guid.entry(npc_guid)),
         :ok <- QuestRequirements.can_take(quest, ctx(state.character)) do
      force_accept(state, quest_id)
    else
      _other -> state
    end
  end

  def force_accept(%{character: %Character{player: player}} = state, quest_id) do
    with %Quest{} = quest <- QuestLoader.get(quest_id),
         {:ok, quest_log} <- QuestLog.add(player.quest_log, quest_id),
         {:ok, state} <- grant_source_item(state, quest) do
      {quest_log, event} =
        QuestLog.evaluate(quest_log, quest, item_counter(state.character.player))

      if event == :completed do
        Network.send_packet(%Message.SmsgQuestupdateComplete{quest_id: quest.id})
      end

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

  def credit_kill(%{character: %Character{} = character} = state, victim_guid) do
    creature_entry = Guid.entry(victim_guid)
    player = character.player

    {quest_log, credited?} =
      Enum.reduce(active_quests(player), {player.quest_log, false}, fn quest, {quest_log, credited?} ->
        case QuestLog.increment_kill(quest_log, quest, creature_entry) do
          {:ok, quest_log, credit} ->
            Network.send_packet(%Message.SmsgQuestupdateAddKill{
              quest_id: quest.id,
              creature_entry: creature_entry,
              count: credit.count,
              required: credit.required,
              victim_guid: victim_guid
            })

            {quest_log, _event} = complete_check(quest_log, quest, player)
            {quest_log, true}

          :no_credit ->
            {quest_log, credited?}
        end
      end)

    if credited? do
      put_character(state, %{character | player: %{player | quest_log: quest_log}})
    else
      state
    end
  end

  def on_inventory_changed(%{character: %Character{} = character} = state, old_player) do
    player = character.player

    quests =
      player
      |> active_quests()
      |> Enum.filter(fn quest -> quest.required_items != [] end)

    if quests == [] do
      state
    else
      send_item_progress(quests, player, old_player)

      {quest_log, changed?} =
        Enum.reduce(quests, {player.quest_log, false}, fn quest, {quest_log, changed?} ->
          case complete_check(quest_log, quest, player) do
            {quest_log, :unchanged} -> {quest_log, changed?}
            {quest_log, _event} -> {quest_log, true}
          end
        end)

      if changed? do
        put_character(state, %{character | player: %{player | quest_log: quest_log}})
      else
        state
      end
    end
  end

  defp send_item_progress(_quests, _player, nil), do: :ok

  defp send_item_progress(quests, player, old_player) do
    quests
    |> Enum.flat_map(fn quest -> quest.required_items end)
    |> Enum.map(fn {_index, item_id, _required} -> item_id end)
    |> Enum.uniq()
    |> Enum.each(fn item_id ->
      delta =
        Inventory.count_entry(player, item_id, &ItemStore.get/1) -
          Inventory.count_entry(old_player, item_id, &ItemStore.get/1)

      if delta > 0 do
        Network.send_packet(%Message.SmsgQuestupdateAddItem{item_id: item_id, count: delta})
      end
    end)
  end

  defp complete_check(quest_log, %Quest{} = quest, player) do
    case QuestLog.evaluate(quest_log, quest, item_counter(player)) do
      {quest_log, :completed} ->
        Network.send_packet(%Message.SmsgQuestupdateComplete{quest_id: quest.id})
        {quest_log, :completed}

      result ->
        result
    end
  end

  defp active_quests(player) do
    player.quest_log
    |> QuestLog.active_entries()
    |> Enum.map(fn %Entry{quest_id: quest_id} -> QuestLoader.get(quest_id) end)
    |> Enum.reject(&is_nil/1)
  end

  defp item_counter(player) do
    fn item_id -> Inventory.count_entry(player, item_id, &ItemStore.get/1) end
  end

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
