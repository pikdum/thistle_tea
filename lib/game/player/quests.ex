defmodule ThistleTea.Game.Player.Quests do
  alias ThistleTea.Character
  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Loot
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
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata

  def ctx(%Character{} = character) do
    %{
      level: character.unit.level,
      race: character.unit.race,
      class: character.unit.class,
      quest_log: character.player.quest_log,
      rewarded_quests: character.player.rewarded_quests
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
        cond do
          icon == QuestDialogStatus.available() ->
            send_details(npc_guid, quest)

          icon in [QuestDialogStatus.reward_rep(), QuestDialogStatus.incomplete()] ->
            send_turn_in_dialog(npc_guid, quest, icon == QuestDialogStatus.reward_rep())

          true ->
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
    case Map.get(player.quest_log, slot) do
      %Entry{quest_id: quest_id} ->
        {:ok, quest_log} = QuestLog.remove(player.quest_log, quest_id)
        put_character(state, %{character | player: %{player | quest_log: quest_log}})

      _entry ->
        state
    end
  end

  def complete_quest(%{character: %Character{} = character} = state, npc_guid, quest_id) do
    with %Quest{} = quest <- ender_quest(npc_guid, quest_id),
         %Entry{} = entry <- QuestLog.get(character.player.quest_log, quest_id) do
      send_turn_in_dialog(npc_guid, quest, entry.status == :complete)
    end

    state
  end

  def request_reward(%{character: %Character{} = character} = state, npc_guid, quest_id) do
    with %Quest{} = quest <- ender_quest(npc_guid, quest_id),
         %Entry{status: :complete} <- QuestLog.get(character.player.quest_log, quest_id) do
      send_offer_reward(npc_guid, quest)
    end

    state
  end

  def choose_reward(%{character: %Character{} = character} = state, npc_guid, quest_id, reward_index) do
    with %Quest{} = quest <- ender_quest(npc_guid, quest_id),
         %Entry{status: :complete} <- QuestLog.get(character.player.quest_log, quest_id),
         {:ok, choice} <- validate_reward_choice(quest, reward_index),
         :ok <- validate_required_money(quest, character),
         :ok <- validate_reward_space(quest, choice, character) do
      turn_in(state, npc_guid, quest, choice)
    else
      {:error, :inventory_full} ->
        InventoryUpdate.send_failure(:inventory_full, 0, 0)
        state

      _other ->
        state
    end
  end

  defp turn_in(state, npc_guid, %Quest{} = quest, choice) do
    state = remove_required_items(state, quest)
    state = grant_reward_items(state, quest, choice)

    character = state.character
    {:ok, quest_log} = QuestLog.remove(character.player.quest_log, quest.id)
    rewarded = MapSet.put(character.player.rewarded_quests, quest.id)

    xp = Experience.quest_xp(quest.level, quest.reward_money_max_level, character.unit.level)
    {character, level_ups} = Character.gain_xp(character, xp)
    Enum.each(level_ups, fn level_up -> Network.send_packet(struct(Message.SmsgLevelupInfo, level_up)) end)

    coinage = max(character.player.coinage + quest.reward_money, 0)

    character = %{
      character
      | player: %{character.player | quest_log: quest_log, rewarded_quests: rewarded, coinage: coinage}
    }

    Metadata.update(state.guid, %{level: character.unit.level})
    Network.send_packet(%Message.SmsgQuestgiverQuestComplete{quest: quest, xp: xp})

    state = put_character(state, character)
    send_next_quest(state, npc_guid, quest)
    state
  end

  defp send_next_quest(state, npc_guid, %Quest{next_quest_in_chain: next_id}) when next_id > 0 do
    with %Quest{} = next_quest <- QuestLoader.get(next_id),
         true <- next_id in QuestLoader.given_by(Guid.entry(npc_guid)),
         :ok <- QuestRequirements.can_take(next_quest, ctx(state.character)) do
      send_details(npc_guid, next_quest)
    end

    :ok
  end

  defp send_next_quest(_state, _npc_guid, %Quest{}), do: :ok

  defp send_turn_in_dialog(npc_guid, %Quest{} = quest, completable) do
    if quest.request_items_text == "" or (quest.required_items == [] and completable) do
      send_offer_reward(npc_guid, quest)
    else
      Network.send_packet(%Message.SmsgQuestgiverRequestItems{
        npc_guid: npc_guid,
        quest: quest,
        completable: completable,
        close_on_cancel: false
      })
    end
  end

  defp send_offer_reward(npc_guid, %Quest{} = quest) do
    Network.send_packet(%Message.SmsgQuestgiverOfferReward{
      npc_guid: npc_guid,
      quest: quest,
      enable_next: true
    })
  end

  defp ender_quest(npc_guid, quest_id) do
    if quest_id in QuestLoader.ended_by(Guid.entry(npc_guid)) do
      QuestLoader.get(quest_id)
    end
  end

  defp validate_reward_choice(%Quest{reward_choice_items: []}, _reward_index), do: {:ok, nil}

  defp validate_reward_choice(%Quest{reward_choice_items: choices}, reward_index)
       when reward_index >= 0 and reward_index < length(choices), do: {:ok, Enum.at(choices, reward_index)}

  defp validate_reward_choice(%Quest{}, _reward_index), do: {:error, :invalid_reward}

  defp validate_required_money(%Quest{reward_money: money}, %Character{player: player})
       when money < 0 and player.coinage < -money, do: {:error, :not_enough_money}

  defp validate_required_money(%Quest{}, %Character{}), do: :ok

  defp validate_reward_space(%Quest{} = quest, choice, %Character{player: player}) do
    rewards = quest.reward_items ++ List.wrap(choice)

    can_store_all =
      Enum.all?(rewards, fn {item_id, count} ->
        case ItemLoader.get_template(item_id) do
          %ItemTemplate{} = template -> Inventory.can_store?(player, template, count, &ItemStore.get/1)
          _template -> true
        end
      end)

    if can_store_all, do: :ok, else: {:error, :inventory_full}
  end

  defp remove_required_items(state, %Quest{required_items: required_items}) do
    Enum.reduce(required_items, state, fn {_index, item_id, count}, state ->
      case Inventory.remove_count(state.character.player, item_id, count, &ItemStore.get/1) do
        {:ok, result} -> InventoryUpdate.apply(state, {:ok, result})
        _error -> state
      end
    end)
  end

  defp grant_reward_items(state, %Quest{} = quest, choice) do
    Enum.reduce(quest.reward_items ++ List.wrap(choice), state, fn {item_id, count}, state ->
      give_item(state, item_id, count)
    end)
  end

  defp give_item(%{guid: guid} = state, item_id, count) do
    case ItemStore.create(item_id, owner: guid, stack_count: count) do
      %DataItem{} = item ->
        case Inventory.store(state.character.player, guid, item, &ItemStore.get/1) do
          {:ok, result, placement} ->
            state = InventoryUpdate.apply(state, {:ok, result})
            send_item_push(state, item, placement, count)
            state

          _error ->
            ItemStore.delete(item.object.guid)
            state
        end

      _error ->
        state
    end
  end

  def needs_item?(%Character{player: player}, item_id) do
    player.quest_log
    |> QuestLog.active_entries()
    |> Enum.any?(fn
      %Entry{quest_id: quest_id, status: :incomplete} ->
        case QuestLoader.get(quest_id) do
          %Quest{required_items: required_items} ->
            Enum.any?(required_items, fn {_index, required_id, required_count} ->
              required_id == item_id and
                Inventory.count_entry(player, item_id, &ItemStore.get/1) < required_count
            end)

          nil ->
            false
        end

      %Entry{} ->
        false
    end)
  end

  def filter_loot(%Loot{} = loot, %Character{} = character) do
    items =
      Enum.filter(loot.items, fn item ->
        not item.quest_item or needs_item?(character, item.item_id)
      end)

    %{loot | items: items}
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
