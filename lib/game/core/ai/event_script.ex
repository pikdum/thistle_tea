defmodule ThistleTea.Game.Core.AI.EventScript do
  @moduledoc """
  Ports of vmangos C++ event scripts, the `ProcessEventId` handlers bound to
  an `event_scripts` id through `scripted_event_id`, written as generic
  script steps.

  An event starts when a player uses a goober or casts a spell that sends it.
  `event_steps/1` returns the steps that event runs: on the player, aimed at
  the object they used or the spell's target. A ported event replaces the
  database rows of its id, as a vmangos handler that claims an event keeps
  the database script from running. A creature script can serve as an event
  script too, when the event only exists to call that creature.
  """

  alias ThistleTea.Game.Core.AI.CreatureScript.TestOfEndurance
  alias ThistleTea.Game.Core.AI.EventScript.AlteracValley
  alias ThistleTea.Game.Core.AI.EventScript.ImpDelivery
  alias ThistleTea.Game.Core.AI.EventScript.PrincipalSource
  alias ThistleTea.Game.Core.AI.EventScript.Uldaman
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep

  @callback event_ids() :: [pos_integer()]
  @callback event_steps(pos_integer()) :: [%ScriptStep{}]

  @scripts [AlteracValley, ImpDelivery, PrincipalSource, TestOfEndurance, Uldaman]

  def steps_by_event do
    for script <- @scripts, event_id <- script.event_ids(), into: %{}, do: {event_id, script.event_steps(event_id)}
  end

  def summon_entries, do: Script.summon_entries(steps())

  def creature_entries, do: Script.creature_entries(steps())

  defp steps, do: steps_by_event() |> Map.values() |> List.flatten()
end
