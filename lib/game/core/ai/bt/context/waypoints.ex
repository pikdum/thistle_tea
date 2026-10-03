defmodule ThistleTea.Game.Core.AI.BT.Context.Waypoints do
  @moduledoc """
  Immutable VMangos waypoint catalog supplied to one behavior-tree tick.
  Besides the vmangos path sources (0 guid or entry, 1 guid, 2 entry,
  3 special), source 4 selects the path of a C++-scripted escort
  (`Core.Quest.QuestEscort`) by the quest id in `dataint3`, so one escortee
  can walk a different path for each of its quests. Source 5 selects the
  path a `Core.AI.CreatureScript` port walks, by the creature entry in
  `dataint2` or the creature's own and the path variant in `dataint3`.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Entity.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Core.Guid

  @enforce_keys [:routes]
  defstruct [:routes]

  def empty, do: new(%{})
  def new(routes) when is_map(routes), do: %__MODULE__{routes: routes}

  def resolve(
        %__MODULE__{routes: routes},
        %{object: %{guid: guid, entry: entry}},
        %ScriptStep{command: :start_waypoints} = step
      ) do
    guid_key = positive_or(step.dataint, Guid.low_guid(guid))
    entry_key = positive_or(step.dataint2, positive_or(entry, Guid.entry(guid)))

    case route(routes, step.datalong, guid_key, entry_key, step.dataint3) do
      %WaypointRoute{} = route -> WaypointRoute.start(route, step.datalong2, step.datalong4 != 0)
      nil -> nil
    end
  end

  def resolve(%__MODULE__{}, _entity, %ScriptStep{}), do: nil

  defp route(routes, 0, guid_key, entry_key, _quest_id),
    do: Map.get(routes, {:guid, guid_key}) || Map.get(routes, {:entry, entry_key})

  defp route(routes, 1, guid_key, _entry_key, _quest_id), do: Map.get(routes, {:guid, guid_key})
  defp route(routes, 2, _guid_key, entry_key, _quest_id), do: Map.get(routes, {:entry, entry_key})
  defp route(routes, 3, _guid_key, entry_key, _quest_id), do: Map.get(routes, {:special, entry_key})
  defp route(routes, 4, _guid_key, _entry_key, quest_id), do: Map.get(routes, {:escort, quest_id})
  defp route(routes, 5, _guid_key, entry_key, variant), do: Map.get(routes, {:script, entry_key, variant})
  defp route(_routes, _source, _guid_key, _entry_key, _quest_id), do: nil

  defp positive_or(value, _fallback) when is_integer(value) and value > 0, do: value
  defp positive_or(_value, fallback), do: fallback
end
