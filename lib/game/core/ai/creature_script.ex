defmodule ThistleTea.Game.Core.AI.CreatureScript do
  @moduledoc """
  Ports of vmangos C++ creature AIs, the `script_name` scripts, written as
  EventAI events so a scripted creature runs through the same event and
  script interpreter as its database-driven peers.

  In vmangos a script name takes priority over EventAI, so a ported creature's
  `creature_ai_events` rows are replaced, not extended. Talk steps carry
  broadcast text ids in `dataint`; the loader resolves them the same way it
  resolves database script talk steps. Like vmangos, EventAI runs an event's
  actions directly and ignores step delays, so `timed/1` wraps a delayed
  sequence in a `start_script` step, the way the database chains generic
  scripts. A script whose creature reacts to a quest being accepted, as
  vmangos `QuestAccept` hooks do, returns the steps to append to that quest's
  start script from `quest_start_steps/0`.
  """

  alias ThistleTea.Game.Core.AI.AIEvent
  alias ThistleTea.Game.Core.AI.CreatureScript.Bartleby
  alias ThistleTea.Game.Core.AI.CreatureScript.ChickenCluck
  alias ThistleTea.Game.Core.AI.CreatureScript.FelwoodOoze
  alias ThistleTea.Game.Core.AI.CreatureScript.LazyPeon
  alias ThistleTea.Game.Core.AI.CreatureScript.SicklyCritter
  alias ThistleTea.Game.Core.AI.CreatureScript.Triage
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep

  @callback entries() :: [pos_integer()]
  @callback events(pos_integer()) :: [%AIEvent{}]
  @callback quest_start_steps() :: %{pos_integer() => [%ScriptStep{}]}

  @optional_callbacks quest_start_steps: 0

  @scripts [Bartleby, ChickenCluck, FelwoodOoze, LazyPeon, SicklyCritter, Triage]
  @timed_script 1

  def ported?(entry), do: not is_nil(script(entry))

  def events(entry) do
    case script(entry) do
      nil -> []
      script -> script.events(entry)
    end
  end

  def entries, do: Enum.flat_map(@scripts, & &1.entries())

  def creature_entries, do: Script.creature_entries(steps())

  def summon_entries, do: Script.summon_entries(steps() ++ Enum.flat_map(quest_start_steps(), &elem(&1, 1)))

  def quest_start_steps do
    @scripts
    |> Enum.filter(&(Code.ensure_loaded?(&1) and function_exported?(&1, :quest_start_steps, 0)))
    |> Enum.map(& &1.quest_start_steps())
    |> Enum.reduce(%{}, &Map.merge(&2, &1, fn _quest_id, steps, more -> steps ++ more end))
  end

  defp steps, do: entries() |> Enum.flat_map(&events/1) |> Enum.flat_map(&List.flatten(&1.actions))

  def event(entry, index, event_type, steps, opts \\ []) when is_integer(entry) and is_list(steps) do
    struct!(
      %AIEvent{id: entry * 100 + index, event_type: event_type, repeatable?: true, actions: [steps]},
      opts
    )
  end

  def timed(steps) when is_list(steps) do
    %ScriptStep{command: :start_script, datalong: @timed_script, dataint: 100, sub_scripts: %{@timed_script => steps}}
  end

  def only_in_phases(phases) when is_list(phases) do
    Enum.reduce(0..31, 0, fn phase, mask ->
      if phase in phases, do: mask, else: Bitwise.bor(mask, Bitwise.bsl(1, phase))
    end)
  end

  defp script(entry), do: Enum.find(@scripts, &(entry in &1.entries()))
end
