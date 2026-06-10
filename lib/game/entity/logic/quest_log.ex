defmodule ThistleTea.Game.Entity.Logic.QuestLog do
  import Bitwise

  alias ThistleTea.Game.Entity.Data.Quest

  @max_slots 20
  @max_counter 63

  @status_bytes %{incomplete: 0, complete: 1, failed: 2}

  defmodule Entry do
    defstruct [:quest_id, status: :incomplete, counts: %{}]
  end

  def max_slots, do: @max_slots

  def increment_kill(quest_log, %Quest{} = quest, creature_entry) do
    with %Entry{status: :incomplete, counts: counts} <- get(quest_log, quest.id),
         {index, _entry, required} <-
           Enum.find(quest.required_kills, fn {_index, entry, _required} ->
             entry == creature_entry
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

  def evaluate(quest_log, %Quest{} = quest, item_count_fn) do
    case get(quest_log, quest.id) do
      %Entry{status: status} = entry when status in [:incomplete, :complete] ->
        satisfied = objectives_satisfied?(quest, entry, item_count_fn)

        cond do
          satisfied and status == :incomplete -> transition(quest_log, quest, :complete)
          not satisfied and status == :complete -> transition(quest_log, quest, :incomplete)
          true -> {quest_log, :unchanged}
        end

      _entry ->
        {quest_log, :unchanged}
    end
  end

  def objectives_satisfied?(%Quest{} = quest, %Entry{counts: counts}, item_count_fn) do
    kills_satisfied =
      Enum.all?(quest.required_kills, fn {index, _entry, required} ->
        Map.get(counts, index, 0) >= required
      end)

    items_satisfied =
      Enum.all?(quest.required_items, fn {_index, item_id, required} ->
        item_count_fn.(item_id) >= required
      end)

    kills_satisfied and items_satisfied
  end

  defp transition(quest_log, %Quest{} = quest, status) do
    {:ok, quest_log} = update(quest_log, quest.id, fn entry -> %{entry | status: status} end)
    event = if status == :complete, do: :completed, else: :incompleted
    {quest_log, event}
  end

  def add(quest_log, quest_id) do
    quest_log = quest_log || %{}

    cond do
      active?(quest_log, quest_id) -> {:error, :already_active}
      free_slot(quest_log) == nil -> {:error, :log_full}
      true -> {:ok, Map.put(quest_log, free_slot(quest_log), %Entry{quest_id: quest_id})}
    end
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
    (quest_log || %{})
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
    (quest_log || %{})
    |> Enum.flat_map(fn
      {_slot, %Entry{} = entry} -> [entry]
      _entry -> []
    end)
  end

  def full?(quest_log), do: free_slot(quest_log || %{}) == nil

  def slot_binary(nil), do: nil
  def slot_binary(:empty), do: <<0::size(96)>>

  def slot_binary(%Entry{quest_id: quest_id, status: status, counts: counts}) do
    counter_word =
      Enum.reduce(counts, @status_bytes[status] <<< 24, fn {index, count}, acc ->
        acc ||| min(count, @max_counter) <<< (6 * index)
      end)

    <<quest_id::little-size(32), counter_word::little-size(32), 0::little-size(32)>>
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
