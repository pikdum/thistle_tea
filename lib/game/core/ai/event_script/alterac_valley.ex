defmodule ThistleTea.Game.Core.AI.EventScript.AlteracValley do
  @moduledoc """
  The ten-player Alterac Valley rituals, Call of the Nether (7060) and
  Call to Ivus (7268). vmangos's altar spells send these events without a
  handler. The completion spell already raises the boss. The nearest summoner
  receives the event and ends the ceremony once, through her phase guard.
  """

  @behaviour ThistleTea.Game.Core.AI.EventScript

  alias ThistleTea.Game.Core.AI.EventScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @impl EventScript
  def event_ids, do: [7_060, 7_268]

  @impl EventScript
  def event_steps(7_060), do: [call(7_060, 13_236)]
  def event_steps(7_268), do: [call(7_268, 13_442)]

  defp call(event, summoner) do
    %ScriptStep{
      command: :send_script_event,
      datalong: event,
      target_type: :nearest_creature_with_entry,
      target_param1: summoner,
      target_param2: 40,
      swap_final?: true,
      condition: %Condition{type: :map_id, value1: 30}
    }
  end
end
