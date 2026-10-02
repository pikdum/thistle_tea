defmodule ThistleTea.Game.Core.Player.PlayedTime do
  @moduledoc """
  Total and current-level time played, as `/played` reports it. The session
  clock folds into both counters whenever they are read or saved; login
  re-anchors it so offline time never counts, and a level change restarts the
  level counter. A character that has never played is on its first login.
  """

  defstruct total_ms: 0, level_ms: 0, since: nil

  def first_login?(%{internal: %{played: %__MODULE__{total_ms: 0}}}), do: true
  def first_login?(_character), do: false

  def start(%{internal: _internal} = character, now), do: put(character, %{played(character) | since: now})

  def fold(%{internal: _internal} = character, now), do: put(character, fold_played(played(character), now))

  def level_changed(%{internal: _internal} = character, now),
    do: put(character, %{fold_played(played(character), now) | level_ms: 0})

  def seconds(%{internal: _internal} = character, now) do
    played = fold_played(played(character), now)
    {div(played.total_ms, 1000), div(played.level_ms, 1000)}
  end

  defp fold_played(%__MODULE__{since: nil} = played, _now), do: played

  defp fold_played(%__MODULE__{since: since} = played, now) do
    elapsed = max(now - since, 0)
    %{played | total_ms: played.total_ms + elapsed, level_ms: played.level_ms + elapsed, since: now}
  end

  defp played(%{internal: %{played: %__MODULE__{} = played}}), do: played

  defp put(%{internal: internal} = character, %__MODULE__{} = played),
    do: %{character | internal: %{internal | played: played}}
end
