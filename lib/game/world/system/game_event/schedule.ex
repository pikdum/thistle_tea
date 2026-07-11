defmodule ThistleTea.Game.World.System.GameEvent.Schedule do
  @moduledoc """
  Pure recurrence calculations for database-backed game events.
  """

  defstruct entries: []

  defmodule Entry do
    @moduledoc false

    @enforce_keys [:id, :starts_at, :ends_at, :occurrence_seconds, :length_seconds]
    defstruct [:id, :starts_at, :ends_at, :occurrence_seconds, :length_seconds, :description]
  end

  def new(entries) when is_list(entries) do
    %__MODULE__{entries: Enum.sort_by(entries, & &1.id)}
  end

  def active_events(%__MODULE__{entries: entries}, %DateTime{} = now) do
    entries
    |> Enum.filter(&active?(&1, now))
    |> Enum.map(& &1.id)
  end

  def next_transition(%__MODULE__{entries: entries}, %DateTime{} = now) do
    entries
    |> Enum.map(&entry_transition(&1, now))
    |> Enum.reject(&is_nil/1)
    |> Enum.min_by(&DateTime.to_unix(&1, :millisecond), fn -> nil end)
  end

  def active?(%Entry{} = entry, %DateTime{} = now) do
    now_seconds = DateTime.to_unix(now)
    start_seconds = DateTime.to_unix(entry.starts_at)
    end_seconds = DateTime.to_unix(entry.ends_at)

    now_seconds >= start_seconds and now_seconds < end_seconds and
      active_in_occurrence?(entry, now_seconds - start_seconds)
  end

  defp active_in_occurrence?(%Entry{} = entry, elapsed_seconds) do
    entry.length_seconds >= entry.occurrence_seconds or
      rem(elapsed_seconds, entry.occurrence_seconds) < entry.length_seconds
  end

  defp entry_transition(%Entry{} = entry, %DateTime{} = now) do
    now_seconds = DateTime.to_unix(now)
    start_seconds = DateTime.to_unix(entry.starts_at)
    end_seconds = DateTime.to_unix(entry.ends_at)

    cond do
      now_seconds >= end_seconds ->
        nil

      now_seconds < start_seconds ->
        entry.starts_at

      entry.length_seconds >= entry.occurrence_seconds ->
        entry.ends_at

      true ->
        recurring_transition(entry, now_seconds, start_seconds, end_seconds)
    end
  end

  defp recurring_transition(%Entry{} = entry, now_seconds, start_seconds, end_seconds) do
    elapsed_seconds = now_seconds - start_seconds
    occurrence_start = start_seconds + div(elapsed_seconds, entry.occurrence_seconds) * entry.occurrence_seconds
    occurrence_end = occurrence_start + entry.length_seconds

    next_seconds =
      if now_seconds < occurrence_end do
        min(occurrence_end, end_seconds)
      else
        min(occurrence_start + entry.occurrence_seconds, end_seconds)
      end

    DateTime.from_unix!(next_seconds)
  end
end
