defmodule ThistleTea.Game.Entity.Logic.AI.BT.Context.Waypoints do
  @moduledoc """
  Immutable VMangos waypoint catalog supplied to one behavior-tree tick.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Guid

  @enforce_keys [:routes]
  defstruct [:routes]

  def empty, do: new(%{})
  def new(routes) when is_map(routes), do: %__MODULE__{routes: routes}

  def resolve(%__MODULE__{routes: routes}, %{object: %{guid: guid}}, %ScriptStep{command: :start_waypoints} = step) do
    guid_key = positive_or(step.dataint, Guid.low_guid(guid))
    entry_key = positive_or(step.dataint2, Guid.entry(guid))

    route =
      case step.datalong do
        0 -> Map.get(routes, {:guid, guid_key}) || Map.get(routes, {:entry, entry_key})
        1 -> Map.get(routes, {:guid, guid_key})
        2 -> Map.get(routes, {:entry, entry_key})
        3 -> Map.get(routes, {:special, entry_key})
        _source -> nil
      end

    case route do
      %WaypointRoute{} -> WaypointRoute.start(route, step.datalong2, step.datalong4 != 0)
      nil -> nil
    end
  end

  def resolve(%__MODULE__{}, _entity, %ScriptStep{}), do: nil

  defp positive_or(value, _fallback) when is_integer(value) and value > 0, do: value
  defp positive_or(_value, fallback), do: fallback
end
