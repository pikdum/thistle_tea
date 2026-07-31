defmodule ThistleTea.Game.Entity.Logic.QuestLog do
  @moduledoc """
  Pure quest-log state: slot management, kill/item objective counting,
  completion evaluation, and packing entries into the client's quest-slot
  update fields.
  """

  import Bitwise

  alias ThistleTea.Game.Entity.Data.Quest

  @max_slots 20
  @max_counter 63

  @status_bytes %{incomplete: 0, complete: 1, failed: 2}

  defmodule Entry do
    @moduledoc false
    defstruct [:quest_id, :expires_at_ms, :client_expires_at, status: :incomplete, counts: %{}, explored?: false]
  end

  def max_slots, do: @max_slots

  def increment_kill(quest_log, %Quest{} = quest, creature_entry) do
    increment_entity_objective(quest_log, quest, :creature, creature_entry, 0)
  end

  def increment_interaction(quest_log, %Quest{} = quest, entity_type, entry)
      when entity_type in [:creature, :game_object] do
    increment_entity_objective(quest_log, quest, entity_type, entry, 0)
  end

  def increment_cast(quest_log, %Quest{} = quest, entity_type, entry, spell_id)
      when entity_type in [:creature, :game_object] and is_integer(spell_id) and spell_id > 0 do
    increment_entity_objective(quest_log, quest, entity_type, entry, spell_id)
  end

  defp increment_entity_objective(quest_log, %Quest{} = quest, entity_type, target_entry, spell_id) do
    with %Entry{status: :incomplete, counts: counts} <- get(quest_log, quest.id),
         {index, ^entity_type, ^target_entry, ^spell_id, required} <-
           Enum.find(entity_objectives(quest), fn
             {_index, ^entity_type, ^target_entry, ^spell_id, _required} -> true
             _objective -> false
           end),
         current when current < required <- Map.get(counts, index, 0) do
      count = current + 1

      {:ok, quest_log} =
        update(quest_log, quest.id, fn entry ->
          %{entry | counts: Map.put(entry.counts, index, count)}
        end)

      {:ok, quest_log, %{index: index, count: count, required: required}}
    else
      _other -> :no_credit
    end
  end

  def evaluate(quest_log, %Quest{} = quest, item_count_fn, reputation_fn \\ fn _faction_id -> 0 end) do
    case get(quest_log, quest.id) do
      %Entry{status: status} = entry when status in [:incomplete, :complete] ->
        satisfied = objectives_satisfied?(quest, entry, item_count_fn, reputation_fn)

        cond do
          satisfied and status == :incomplete -> transition(quest_log, quest, :complete)
          not satisfied and status == :complete -> transition(quest_log, quest, :incomplete)
          true -> {quest_log, :unchanged}
        end

      _entry ->
        {quest_log, :unchanged}
    end
  end

  def objectives_satisfied?(
        %Quest{} = quest,
        %Entry{counts: counts} = entry,
        item_count_fn,
        reputation_fn \\ fn _ -> 0 end
      ) do
    entities_satisfied =
      Enum.all?(entity_objectives(quest), fn {index, _entity_type, _entry, _spell_id, required} ->
        Map.get(counts, index, 0) >= required
      end)

    items_satisfied =
      Enum.all?(quest.required_items, fn {_index, item_id, required} ->
        item_count_fn.(item_id) >= required
      end)

    exploration_satisfied = not Quest.exploration?(quest) or entry.explored?

    reputation_satisfied =
      quest.reputation_objective_faction <= 0 or
        reputation_fn.(quest.reputation_objective_faction) >= quest.reputation_objective_value

    entities_satisfied and items_satisfied and exploration_satisfied and reputation_satisfied
  end

  def mark_explored(quest_log, quest_id) do
    case get(quest_log, quest_id) do
      %Entry{status: :incomplete, explored?: false} ->
        update(quest_log, quest_id, fn entry -> %{entry | explored?: true} end)

      %Entry{} ->
        {:error, :no_change}

      nil ->
        {:error, :not_active}
    end
  end

  defp transition(quest_log, %Quest{} = quest, status) do
    {:ok, quest_log} = update(quest_log, quest.id, fn entry -> %{entry | status: status} end)
    event = if status == :complete, do: :completed, else: :incompleted
    {quest_log, event}
  end

  defp entity_objectives(%Quest{required_entity_objectives: [_objective | _rest] = objectives}), do: objectives

  defp entity_objectives(%Quest{required_kills: required_kills}) do
    Enum.map(required_kills, fn {index, entry, required} ->
      {index, :creature, entry, 0, required}
    end)
  end

  def add(quest_log, quest_id) do
    cond do
      active?(quest_log, quest_id) -> {:error, :already_active}
      free_slot(quest_log) == nil -> {:error, :log_full}
      true -> {:ok, Map.put(quest_log, free_slot(quest_log), %Entry{quest_id: quest_id})}
    end
  end

  def add(quest_log, %Quest{limit_time: limit_time} = quest, now_ms, unix_seconds)
      when limit_time > 0 and is_integer(now_ms) and is_integer(unix_seconds) do
    with {:ok, quest_log} <- add(quest_log, quest.id) do
      update(quest_log, quest.id, fn entry ->
        %{
          entry
          | expires_at_ms: now_ms + limit_time * 1_000,
            client_expires_at: unix_seconds + limit_time
        }
      end)
    end
  end

  def add(quest_log, %Quest{} = quest, now_ms, unix_seconds) when is_integer(now_ms) and is_integer(unix_seconds) do
    add(quest_log, quest.id)
  end

  def fail_timed(quest_log, quest_id, now_ms) when is_integer(now_ms) do
    case get(quest_log, quest_id) do
      %Entry{status: status, expires_at_ms: expires_at_ms}
      when status in [:incomplete, :complete] and is_integer(expires_at_ms) and expires_at_ms <= now_ms ->
        update(quest_log, quest_id, fn entry ->
          %{entry | status: :failed, expires_at_ms: nil, client_expires_at: 1}
        end)

      %Entry{} ->
        {:error, :not_expired}

      nil ->
        {:error, :not_active}
    end
  end

  def timed?(quest_log) do
    Enum.any?(active_entries(quest_log), &is_integer(&1.expires_at_ms))
  end

  def timed_entries(quest_log) do
    Enum.filter(active_entries(quest_log), &is_integer(&1.expires_at_ms))
  end

  def remove(quest_log, quest_id) do
    case find(quest_log, quest_id) do
      {slot, %Entry{}} -> {:ok, Map.put(quest_log, slot, :empty)}
      nil -> {:error, :not_active}
    end
  end

  def update(quest_log, quest_id, fun) do
    case find(quest_log, quest_id) do
      {slot, %Entry{} = entry} -> {:ok, Map.put(quest_log, slot, fun.(entry))}
      nil -> {:error, :not_active}
    end
  end

  def find(quest_log, quest_id) do
    quest_log
    |> Enum.find(fn
      {_slot, %Entry{quest_id: ^quest_id}} -> true
      _entry -> false
    end)
  end

  def get(quest_log, quest_id) do
    case find(quest_log, quest_id) do
      {_slot, %Entry{} = entry} -> entry
      nil -> nil
    end
  end

  def active?(quest_log, quest_id), do: find(quest_log, quest_id) != nil

  def active_entries(quest_log) do
    quest_log
    |> Enum.flat_map(fn
      {_slot, %Entry{} = entry} -> [entry]
      _entry -> []
    end)
  end

  def full?(quest_log), do: free_slot(quest_log) == nil

  def slot_binary(nil), do: nil
  def slot_binary(:empty), do: <<0::size(96)>>

  def slot_binary(%Entry{quest_id: quest_id, status: status, counts: counts, client_expires_at: client_expires_at}) do
    counter_word =
      Enum.reduce(counts, @status_bytes[status] <<< 24, fn {index, count}, acc ->
        acc ||| min(count, @max_counter) <<< (6 * index)
      end)

    <<quest_id::little-size(32), counter_word::little-size(32), client_expires_at || 0::little-size(32)>>
  end

  defp free_slot(quest_log) do
    Enum.find(0..(@max_slots - 1), fn slot ->
      case Map.get(quest_log, slot) do
        nil -> true
        :empty -> true
        %Entry{} -> false
      end
    end)
  end
end
