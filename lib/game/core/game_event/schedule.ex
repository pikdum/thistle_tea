defmodule ThistleTea.Game.Core.GameEvent.Schedule do
  @moduledoc """
  Pure recurrence calculations for game events. An entry recurs on its
  database row's start, end, occurrence, and length, unless it carries a
  `Core.GameEvent.Rule`, whose calendar it follows instead: rule-driven events
  change state at UTC midnight.
  """

  @rule_horizon_days 92

  defstruct entries: []

  defmodule Entry do
    @moduledoc false

    @enforce_keys [:id]
    defstruct [:id, :starts_at, :ends_at, :occurrence_seconds, :length_seconds, :description, :rule]
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

  def active?(%Entry{rule: rule} = entry, %DateTime{} = now) when not is_nil(rule) do
    rule_active?(entry, DateTime.to_date(now))
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

  defp entry_transition(%Entry{rule: rule} = entry, %DateTime{} = now) when not is_nil(rule) do
    today = DateTime.to_date(now)
    active? = rule_active?(entry, today)

    1..@rule_horizon_days
    |> Stream.map(&Date.add(today, &1))
    |> Enum.find(&(rule_active?(entry, &1) != active?))
    |> case do
      %Date{} = date -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      nil -> nil
    end
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

  defp rule_active?(%Entry{id: id, rule: rule}, %Date{} = date), do: id in rule.active_events(date)
end
