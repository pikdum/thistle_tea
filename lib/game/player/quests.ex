defmodule ThistleTea.Game.Player.Quests do
  @moduledoc """
  Player-session quest flows: questgiver hello/details/accept/complete/reward
  exchanges, quest-log changes, and the packets each step sends.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Logic.Condition, as: ConditionEvaluator
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet.Placement
  alias ThistleTea.Game.Entity.Logic.QuestDialogStatus
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.QuestLog.Entry
  alias ThistleTea.Game.Entity.Logic.QuestRequirements
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Player.ConditionContext
  alias ThistleTea.Game.Player.Mail
  alias ThistleTea.Game.Player.Reputation, as: PlayerReputation
  alias ThistleTea.Game.Player.Stats, as: PlayerStats
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  defmodule Availability do
    @moduledoc false
    defstruct [:quest_context, condition_results: %{}]
  end

  def ctx(%Character{} = character) do
    %{
      level: character.unit.level,
      race: character.unit.race,
      class: character.unit.class,
      quest_log: character.player.quest_log,
      rewarded_quests: character.player.rewarded_quests,
      reputation: PlayerReputation.standings(character)
    }
  end

  def dialog_status(npc_guid, %Character{} = character) do
    if PlayerReputation.can_interact?(character, npc_guid) do
      {giver_quests, ender_quests} = npc_quests(npc_guid)
      availability = availability(character, giver_quests)

      QuestDialogStatus.for_npc(
        giver_quests,
        ender_quests,
        availability.quest_context,
        availability.condition_results
      )
    else
      QuestDialogStatus.none()
    end
  end

  def hello(state, npc_guid) do
    if PlayerReputation.can_interact?(state.character, npc_guid) do
      do_hello(state, npc_guid)
    else
      state
    end
  end

  defp do_hello(state, npc_guid) do
    state = credit_entity_interaction(state, npc_guid)

    case quest_menu(npc_guid, state.character) do
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

    with true <- PlayerReputation.can_interact?(state.character, npc_guid),
         %Quest{} = quest <- QuestLoader.get(quest_id),
         true <-
           quest_id in QuestLoader.given_by(entry) or quest_id in QuestLoader.ended_by(entry) do
      send_details(npc_guid, quest)
    end

    state
  end

  def accept(state, npc_guid, quest_id) do
    with true <- PlayerReputation.can_interact?(state.character, npc_guid),
         %Quest{} = quest <- QuestLoader.get(quest_id),
         true <- quest_id in QuestLoader.given_by(Guid.entry(npc_guid)),
         :ok <- takeability(state.character, quest) do
      force_accept(state, quest_id, npc_guid)
    else
      {:error, :required_condition} ->
        send_condition_invalid()
        state

      {:error, {:required_condition_unknown, _reasons}} ->
        send_condition_invalid()
        state

      _other ->
        state
    end
  end

  def force_accept(state, quest_id), do: force_accept(state, quest_id, nil)

  def force_accept(%{character: %Character{player: player}} = state, quest_id, source_guid) do
    with %Quest{} = quest <- QuestLoader.get(quest_id),
         {:ok, quest_log} <-
           QuestLog.add(player.quest_log, quest, Time.now(), System.system_time(:second)),
         {:ok, state} <- grant_source_item(state, quest) do
      {quest_log, event} =
        QuestLog.evaluate(
          quest_log,
          quest,
          item_counter(state.character.player),
          &PlayerReputation.standing(state.character, &1)
        )

      if event == :completed do
        Network.send_packet(%Message.SmsgQuestupdateComplete{quest_id: quest.id})
      end

      character = state.character
      character = %{character | player: %{character.player | quest_log: quest_log}}
      state = put_character(state, character)

      state =
        if quest.reputation_objective_faction > 0 do
          PlayerReputation.set_visible(state, quest.reputation_objective_faction)
        else
          state
        end

      state
      |> schedule_timer(quest.id)
      |> run_quest_script(source_guid, quest.start_script_steps)
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

  def restore_timers(%{character: %Character{player: player}} = state) do
    Enum.reduce(QuestLog.timed_entries(player.quest_log), state, fn entry, state ->
      schedule_timer(state, entry.quest_id)
    end)
  end

  def expire_timed(%{character: %Character{player: player} = character} = state, quest_id, expected_expires_at) do
    case QuestLog.get(player.quest_log, quest_id) do
      %Entry{expires_at_ms: ^expected_expires_at} ->
        case QuestLog.fail_timed(player.quest_log, quest_id, Time.now()) do
          {:ok, quest_log} ->
            Network.send_packet(%Message.SmsgQuestupdateFailedtimer{quest_id: quest_id})
            put_character(state, %{character | player: %{player | quest_log: quest_log}})

          {:error, :not_expired} ->
            schedule_timer(state, quest_id)

          _error ->
            state
        end

      _stale ->
        state
    end
  end

  defp schedule_timer(%{character: %Character{player: player}} = state, quest_id) do
    case QuestLog.get(player.quest_log, quest_id) do
      %Entry{expires_at_ms: expires_at_ms} when is_integer(expires_at_ms) ->
        delay_ms = max(expires_at_ms - Time.now(), 0)
        Process.send_after(self(), {:quest_timer_expired, quest_id, expires_at_ms}, delay_ms)
        state

      _entry ->
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
    with true <- PlayerReputation.can_interact?(character, npc_guid),
         %Quest{} = quest <- ender_quest(npc_guid, quest_id),
         %Entry{} = entry <- QuestLog.get(character.player.quest_log, quest_id) do
      send_turn_in_dialog(npc_guid, quest, entry.status == :complete)
    end

    state
  end

  def request_reward(%{character: %Character{} = character} = state, npc_guid, quest_id) do
    with true <- PlayerReputation.can_interact?(character, npc_guid),
         %Quest{} = quest <- ender_quest(npc_guid, quest_id),
         %Entry{status: :complete} <- QuestLog.get(character.player.quest_log, quest_id) do
      send_offer_reward(npc_guid, quest)
    end

    state
  end

  def choose_reward(%{character: %Character{} = character} = state, npc_guid, quest_id, reward_index) do
    with true <- PlayerReputation.can_interact?(character, npc_guid),
         %Quest{} = quest <- ender_quest(npc_guid, quest_id),
         %Entry{status: :complete} <- QuestLog.get(character.player.quest_log, quest_id),
         {:ok, choice} <- validate_reward_choice(quest, reward_index),
         :ok <- validate_required_money(quest, character),
         {:ok, change_set, rewards} <- plan_turn_in_inventory(character, quest, choice) do
      turn_in(state, npc_guid, quest, change_set, rewards)
    else
      {:error, :inventory_full} ->
        InventoryUpdate.send_failure(:inventory_full, 0, 0)
        state

      _other ->
        state
    end
  end

  defp turn_in(state, npc_guid, %Quest{} = quest, %ChangeSet{} = change_set, rewards) do
    {:ok, quest_log} = QuestLog.remove(change_set.player.quest_log, quest.id)
    rewarded = MapSet.put(change_set.player.rewarded_quests, quest.id)

    {xp, money} = quest_reward(quest, state.character.unit.level)
    coinage = max(change_set.player.coinage + money, 0)

    player = %{change_set.player | quest_log: quest_log, rewarded_quests: rewarded, coinage: coinage}
    change_set = ChangeSet.put_player(change_set, player)
    state = InventoryUpdate.apply(state, {:ok, change_set})
    send_reward_pushes(state, change_set, rewards)

    {character, level_ups} = PlayerStats.gain_xp(state.character, xp)
    Enum.each(level_ups, fn level_up -> Network.send_packet(struct(Message.SmsgLevelupInfo, level_up)) end)

    Network.send_packet(%Message.SmsgQuestgiverQuestComplete{quest: quest, xp: xp, money: money})
    state = put_character(state, character)
    state = PlayerReputation.reward_quest(state, quest)
    state = Mail.send_quest_reward(state, npc_guid, quest)
    state = run_quest_script(state, npc_guid, quest.complete_script_steps)
    send_next_quest(state, npc_guid, quest)
    state
  end

  defp run_quest_script(state, source_guid, steps)
       when is_integer(source_guid) and source_guid > 0 and is_list(steps) and steps != [] do
    Entity.start_script(source_guid, steps, state.guid)
    state
  end

  defp run_quest_script(state, _source_guid, _steps), do: state

  defp quest_reward(%Quest{} = quest, player_level) do
    if player_level >= PlayerStats.max_level() do
      {0, quest.reward_money + quest.reward_money_max_level}
    else
      {Experience.quest_xp(quest.level, quest.reward_xp, player_level), quest.reward_money}
    end
  end

  defp send_next_quest(state, npc_guid, %Quest{next_quest_in_chain: next_id}) when next_id > 0 do
    with %Quest{} = next_quest <- QuestLoader.get(next_id),
         true <- next_id in QuestLoader.given_by(Guid.entry(npc_guid)),
         :ok <- takeability(state.character, next_quest) do
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

  defp plan_turn_in_inventory(%Character{object: %{guid: owner}, player: player}, %Quest{} = quest, choice) do
    with {:ok, rewards} <- prepare_rewards(quest.reward_items ++ List.wrap(choice), owner) do
      batch =
        Enum.reduce(quest.required_items, Batch.new(player), fn {_index, item_id, count}, batch ->
          Batch.remove(batch, item_id, count)
        end)

      batch = Enum.reduce(rewards, batch, fn {%DataItem{} = item, _count}, batch -> Batch.add(batch, item) end)

      case Inventory.plan(batch, &ItemStore.get/1) do
        {:ok, change_set} -> {:ok, change_set, rewards}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp prepare_rewards(rewards, owner) do
    Enum.reduce_while(rewards, {:ok, []}, fn {item_id, count}, {:ok, prepared} ->
      case ItemStore.prepare(item_id, owner: owner, stack_count: count) do
        %DataItem{} = item -> {:cont, {:ok, [{item, count} | prepared]}}
        nil -> {:halt, {:error, :invalid_reward}}
      end
    end)
    |> case do
      {:ok, prepared} -> {:ok, Enum.reverse(prepared)}
      error -> error
    end
  end

  defp send_reward_pushes(state, %ChangeSet{} = change_set, rewards) do
    Enum.each(rewards, fn {%DataItem{} = item, count} ->
      placed_at =
        case ChangeSet.placement(change_set, item.object.guid) do
          %Placement{status: :placed, position: position} -> position
          %Placement{status: :merged} -> {Inventory.bag_0(), 0xFFFFFFFF}
        end

      send_item_push(state, item, placed_at, count)
    end)
  end

  def needs_item?(%Character{} = character, item_id) do
    MapSet.member?(needed_items(character), item_id)
  end

  def needed_items(%Character{player: player}) do
    player.quest_log
    |> QuestLog.active_entries()
    |> Enum.flat_map(fn
      %Entry{quest_id: quest_id, status: :incomplete} -> missing_items(player, quest_id)
      %Entry{} -> []
    end)
    |> MapSet.new()
  end

  def sync_needed_items(%Character{} = character) do
    previous_subject =
      case Metadata.query(character.object.guid, [:condition_subject]) do
        %{condition_subject: condition_subject} -> condition_subject
        _missing -> nil
      end

    Presence.sync(character, %{
      needed_quest_items: needed_items(character),
      condition_subject: ConditionContext.refresh_subject(character, previous_subject)
    })

    character
  end

  defp missing_items(player, quest_id) do
    case QuestLoader.get(quest_id) do
      %Quest{required_items: required_items} ->
        for {_index, item_id, required_count} <- required_items,
            Inventory.count_entry(player, item_id, &ItemStore.get/1) < required_count,
            do: item_id

      nil ->
        []
    end
  end

  def npc_quests(npc_guid) do
    entry = Guid.entry(npc_guid)
    {load_quests(QuestLoader.given_by(entry)), load_quests(QuestLoader.ended_by(entry))}
  end

  def quest_menu(npc_guid, %Character{} = character) do
    {giver_quests, ender_quests} = npc_quests(npc_guid)
    availability = availability(character, giver_quests)

    QuestDialogStatus.menu(
      giver_quests,
      ender_quests,
      availability.quest_context,
      availability.condition_results
    )
  end

  def availability(%Character{} = character, quests) when is_list(quests) do
    conditions = quests |> Enum.map(& &1.required_condition) |> Enum.reject(&is_nil/1)
    context = ConditionContext.build(character, conditions, source: nil)

    condition_results =
      quests
      |> Enum.reject(&is_nil(&1.required_condition))
      |> Map.new(fn quest -> {quest.id, ConditionEvaluator.evaluate(context, quest.required_condition)} end)

    %Availability{quest_context: ctx(character), condition_results: condition_results}
  end

  def send_details(npc_guid, %Quest{} = quest) do
    Network.send_packet(%Message.SmsgQuestgiverQuestDetails{
      npc_guid: npc_guid,
      quest: quest,
      activate_accept: true
    })
  end

  defp takeability(%Character{} = character, %Quest{} = quest) do
    availability = availability(character, [quest])
    result = Map.get(availability.condition_results, quest.id)
    QuestRequirements.can_take(quest, availability.quest_context, result)
  end

  defp send_condition_invalid do
    Network.send_packet(%Message.SmsgQuestgiverQuestInvalid{reason: 0})
  end

  defp send_quest_list(npc_guid, entries) do
    Network.send_packet(%Message.SmsgQuestgiverQuestList{
      npc_guid: npc_guid,
      title: "",
      entries: entries
    })
  end

  def explore_area(%{character: %Character{} = character} = state, quest_id) do
    player = character.player

    with %Quest{} = quest <- QuestLoader.get(quest_id),
         true <- Quest.exploration?(quest),
         {:ok, quest_log} <- QuestLog.mark_explored(player.quest_log, quest_id) do
      {quest_log, _event} = complete_check(quest_log, quest, character)
      put_character(state, %{character | player: %{player | quest_log: quest_log}})
    else
      _other -> state
    end
  end

  def credit_kill(%{character: %Character{}} = state, victim_guid) do
    credit_kill_entry(state, Guid.entry(victim_guid), victim_guid)
  end

  def credit_kill_entry(%{character: %Character{} = character} = state, creature_entry, victim_guid) do
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

            {quest_log, _event} = complete_check(quest_log, quest, character)
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

  def credit_entity_interaction(
        %{character: %Character{player: %{quest_log: quest_log}} = character} = state,
        target_guid
      )
      when is_map(quest_log) do
    credit_entity_objective(state, character, target_guid, 0, &QuestLog.increment_interaction/4)
  end

  def credit_entity_interaction(state, _target_guid), do: state

  def credit_cast(%{character: %Character{player: %{quest_log: quest_log}}} = state, target_guids, spell_id)
      when is_map(quest_log) and is_list(target_guids) and is_integer(spell_id) and spell_id > 0 do
    Enum.reduce(target_guids, state, fn target_guid, state ->
      credit_entity_objective(state, state.character, target_guid, spell_id, &QuestLog.increment_cast/5)
    end)
  end

  def credit_cast(state, target_guids, spell_id) when is_list(target_guids) and is_integer(spell_id) and spell_id > 0 do
    state
  end

  def credit_event(%{character: %Character{player: %{quest_log: quest_log}}} = state, quest_id)
      when is_map(quest_log) do
    explore_area(state, quest_id)
  end

  def credit_event(state, _quest_id), do: state

  def credit_scripted_event(state, quest_id, true, distance, world_object_guid) do
    case party_members(state.guid) do
      nil ->
        credit_scripted_event_member(state, quest_id, distance, world_object_guid)

      members ->
        state = credit_scripted_event_member(state, quest_id, distance, world_object_guid)
        send_to_other_members(members, state.guid, {:quest_group_event_credit, quest_id, distance, world_object_guid})
        state
    end
  end

  def credit_scripted_event(state, quest_id, false, distance, world_object_guid) do
    credit_scripted_event_member(state, quest_id, distance, world_object_guid)
  end

  def credit_scripted_event_member(
        %{character: %Character{} = character} = state,
        quest_id,
        distance,
        world_object_guid
      ) do
    if within_script_distance?(character, world_object_guid, distance) do
      credit_event(state, quest_id)
    else
      fail_member(state, quest_id)
    end
  end

  def credit_scripted_kill(state, creature_entry, true) do
    case party_members(state.guid) do
      nil ->
        credit_kill_entry(state, creature_entry, 0)

      members ->
        state = credit_scripted_kill_member(state, creature_entry, state.guid)
        send_to_other_members(members, state.guid, {:quest_group_kill_credit, creature_entry, state.guid})
        state
    end
  end

  def credit_scripted_kill(state, creature_entry, false) do
    credit_kill_entry(state, creature_entry, 0)
  end

  def credit_scripted_kill_member(%{character: %Character{} = character} = state, creature_entry, source_guid) do
    distance = if source_guid == state.guid, do: 0.0, else: World.distance_between(character, source_guid)

    if not Death.ghost?(character) and is_number(distance) and distance <= Experience.group_reward_distance() do
      credit_kill_entry(state, creature_entry, 0)
    else
      state
    end
  end

  def fail(state, quest_id, true) do
    state = fail_member(state, quest_id)

    state.guid
    |> party_members()
    |> send_to_other_members(state.guid, {:quest_fail_member, quest_id})

    state
  end

  def fail(state, quest_id, false), do: fail_member(state, quest_id)

  def fail_member(%{character: %Character{player: player} = character} = state, quest_id) do
    case QuestLog.fail(player.quest_log, quest_id) do
      {:ok, quest_log, timed?} ->
        message =
          if timed? do
            %Message.SmsgQuestupdateFailedtimer{quest_id: quest_id}
          else
            %Message.SmsgQuestupdateFailed{quest_id: quest_id}
          end

        Network.send_packet(message)
        put_character(state, %{character | player: %{player | quest_log: quest_log}})

      _error ->
        state
    end
  end

  defp within_script_distance?(_character, _world_object_guid, distance) when not is_integer(distance) or distance <= 0,
    do: true

  defp within_script_distance?(_character, world_object_guid, _distance) when not is_integer(world_object_guid),
    do: true

  defp within_script_distance?(character, world_object_guid, distance) do
    case World.distance_between(character, world_object_guid) do
      actual when is_number(actual) -> actual <= distance
      _distance -> false
    end
  end

  defp party_members(player_guid) do
    case PartySystem.group_of(player_guid) do
      %Group{members: members} -> Enum.map(members, & &1.guid)
      _group -> nil
    end
  end

  defp send_to_other_members(nil, _player_guid, _message), do: :ok

  defp send_to_other_members(member_guids, player_guid, message) do
    member_guids
    |> Enum.reject(&(&1 == player_guid))
    |> Enum.each(fn guid ->
      case Entity.pid(guid) do
        pid when is_pid(pid) -> send(pid, message)
        _pid -> :ok
      end
    end)
  end

  defp credit_entity_objective(state, %Character{} = character, target_guid, spell_id, increment) do
    entity_type = quest_entity_type(target_guid)
    target_entry = Guid.entry(target_guid)
    player = character.player

    {quest_log, credited?} =
      Enum.reduce(active_quests(player), {player.quest_log, false}, fn quest, {quest_log, credited?} ->
        result =
          case spell_id do
            0 -> increment.(quest_log, quest, entity_type, target_entry)
            spell_id -> increment.(quest_log, quest, entity_type, target_entry, spell_id)
          end

        case result do
          {:ok, quest_log, credit} ->
            send_entity_credit(quest, target_guid, target_entry, credit)
            {quest_log, _event} = complete_check(quest_log, quest, character)
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

  defp send_entity_credit(quest, target_guid, target_entry, credit) do
    Network.send_packet(%Message.SmsgQuestupdateAddKill{
      quest_id: quest.id,
      creature_entry: target_entry,
      count: credit.count,
      required: credit.required,
      victim_guid: target_guid
    })
  end

  defp quest_entity_type(guid) do
    case Guid.entity_type(guid) do
      :mob -> :creature
      type -> type
    end
  end

  def quest_item_counts(%Character{player: player}) do
    player
    |> active_quests()
    |> Enum.flat_map(fn quest -> quest.required_items end)
    |> Enum.map(fn {_index, item_id, _required} -> item_id end)
    |> Enum.uniq()
    |> Map.new(fn item_id -> {item_id, Inventory.count_entry(player, item_id, &ItemStore.get/1)} end)
  end

  def on_inventory_changed(%{character: %Character{} = character} = state, old_counts) do
    player = character.player
    sync_needed_items(character)

    quests =
      player
      |> active_quests()
      |> Enum.filter(fn quest -> quest.required_items != [] end)

    if quests == [] do
      state
    else
      send_item_progress(quests, player, old_counts)

      {quest_log, changed?} =
        Enum.reduce(quests, {player.quest_log, false}, fn quest, {quest_log, changed?} ->
          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
          case complete_check(quest_log, quest, character) do
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

  def on_reputation_changed(%{character: %Character{} = character} = state) do
    quests =
      character.player
      |> active_quests()
      |> Enum.filter(&(&1.reputation_objective_faction > 0))

    {quest_log, changed?} =
      Enum.reduce(quests, {character.player.quest_log, false}, fn quest, {quest_log, changed?} ->
        case complete_check(quest_log, quest, character) do
          {quest_log, :unchanged} -> {quest_log, changed?}
          {quest_log, _event} -> {quest_log, true}
        end
      end)

    if changed? do
      put_character(state, %{character | player: %{character.player | quest_log: quest_log}})
    else
      state
    end
  end

  defp send_item_progress(_quests, _player, nil), do: :ok

  defp send_item_progress(quests, player, old_counts) do
    quests
    |> Enum.flat_map(fn quest -> quest.required_items end)
    |> Enum.map(fn {_index, item_id, _required} -> item_id end)
    |> Enum.uniq()
    |> Enum.each(fn item_id ->
      delta = Inventory.count_entry(player, item_id, &ItemStore.get/1) - Map.get(old_counts, item_id, 0)

      if delta > 0 do
        Network.send_packet(%Message.SmsgQuestupdateAddItem{item_id: item_id, count: delta})
      end
    end)
  end

  defp complete_check(quest_log, %Quest{} = quest, %Character{} = character) do
    case QuestLog.evaluate(
           quest_log,
           quest,
           item_counter(character.player),
           &PlayerReputation.standing(character, &1)
         ) do
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
            placed_at = InventoryUpdate.commit_placement(item, placement)
            state = InventoryUpdate.apply(state, {:ok, result}, placement)
            send_item_push(state, item, placed_at, count)
            {:ok, state}

          _error ->
            ItemStore.delete(item.object.guid)
            {:error, :inventory_full}
        end

      _error ->
        {:ok, state}
    end
  end

  defp send_item_push(state, %DataItem{} = item, {bag_slot, item_slot}, count) do
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
    CharacterStore.put(character)
    sync_needed_items(character)
    PlayerServer.maybe_broadcast_update(%{state | character: Core.mark_broadcast_update(character)})
  end
end
