defmodule ThistleTea.Game.Core.GameEvent.DragonsOfNightmare do
  @moduledoc """
  vmangos `DragonsOfNightmare`, the hardcoded game event 66 that brings
  Ysondre, Lethon, Emeriss, and Taerar to the Emerald Dream portals.

  vmangos starts the event at once on a fresh realm, stops it when all four
  dragons are dead, and starts it again four to seven days later with the
  dragons shuffled between the portals. A world here lasts only until the
  server restarts, which is also when the dragons return, so the event is
  always on and each dragon keeps its database portal.
  """

  @behaviour ThistleTea.Game.Core.GameEvent.Rule

  alias ThistleTea.Game.Core.GameEvent.Rule

  @dragons_of_nightmare 66

  @impl Rule
  def events, do: [@dragons_of_nightmare]

  @impl Rule
  def active_events(%DateTime{}, _scheduled), do: [@dragons_of_nightmare]

  @impl Rule
  def boundaries(%DateTime{}), do: []
end
