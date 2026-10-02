defmodule ThistleTea.Game.Core.GameEvent.Rule do
  @moduledoc """
  The calendar of a hardcoded game event. vmangos starts and stops these from
  code instead of from their `game_event` rows' recurrence, so a rule names the
  events it owns and says which of them a calendar day keeps active.
  """

  alias ThistleTea.Game.Core.GameEvent.DarkmoonFaire

  @callback events() :: [integer()]
  @callback active_events(Date.t()) :: [integer()]

  @rules [DarkmoonFaire]

  def for_event(id) when is_integer(id), do: Enum.find(@rules, &(id in &1.events()))

  def events, do: Enum.flat_map(@rules, & &1.events())
end
