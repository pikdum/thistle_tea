defmodule ThistleTea.Game.Entity.Logic.QuestLog do
  import Bitwise

  @max_slots 20
  @max_counter 63

  @status_bytes %{incomplete: 0, complete: 1, failed: 2}

  defmodule Entry do
    defstruct [:quest_id, status: :incomplete, counts: %{}]
  end

  def max_slots, do: @max_slots

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
