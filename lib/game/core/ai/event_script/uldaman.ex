defmodule ThistleTea.Game.Core.AI.EventScript.Uldaman do
  @moduledoc """
  The Uldaman altar events, `event_awaken_stone_keeper` (2228) and
  `event_awaken_archaedas` (2268), which vmangos names in
  `scripted_event_id` but no longer ships.

  Each altar is a summoning ritual: once three adventurers kneel at it, the
  first casts the spell that sends its event. The Altar of the Keepers starts
  the Stone Keepers and the Altar of Archaedas wakes Archaedas, both through
  `InstanceScript.Uldaman`.
  """

  @behaviour ThistleTea.Game.Core.AI.EventScript

  alias ThistleTea.Game.Core.AI.EventScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @awaken_stone_keeper 2_228
  @awaken_archaedas 2_268
  @stone_keepers 1
  @archaedas 2
  @in_progress 1

  @impl EventScript
  def event_ids, do: [@awaken_stone_keeper, @awaken_archaedas]

  @impl EventScript
  def event_steps(@awaken_stone_keeper), do: [start(@stone_keepers)]
  def event_steps(@awaken_archaedas), do: [start(@archaedas)]

  defp start(field), do: %ScriptStep{command: :set_instance_data, datalong: field, datalong2: @in_progress}
end
