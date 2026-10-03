defmodule ThistleTea.Game.Core.GameEvent.Rule do
  @moduledoc """
  The calendar of a hardcoded game event. vmangos starts and stops these from
  code instead of from their `game_event` rows' recurrence, so a rule names the
  events it owns and says which of them are active at a moment, given the
  database-scheduled events active then. `boundaries/1` lists, in order, the
  coming moments its answer can change at; a change the scheduled events
  cause is found through their own transitions, so a rule that follows them
  only needs to look as far ahead as its own clock reaches. A rule may also
  claim events that world state rather than the clock decides; it never
  starts them, and their driver holds them through `World.System.GameEvent.drive/2`.
  """

  alias ThistleTea.Game.Core.GameEvent.DarkmoonFaire
  alias ThistleTea.Game.Core.GameEvent.DragonsOfNightmare
  alias ThistleTea.Game.Core.GameEvent.ElementalInvasion
  alias ThistleTea.Game.Core.GameEvent.FireworksShow
  alias ThistleTea.Game.Core.GameEvent.WarEffort

  @callback events() :: [integer()]
  @callback active_events(DateTime.t(), MapSet.t(integer())) :: [integer()]
  @callback boundaries(DateTime.t()) :: Enumerable.t(DateTime.t())

  @rules [DarkmoonFaire, DragonsOfNightmare, ElementalInvasion, FireworksShow, WarEffort]

  def for_event(id) when is_integer(id), do: Enum.find(@rules, &(id in &1.events()))

  def events, do: Enum.flat_map(@rules, & &1.events())
end
