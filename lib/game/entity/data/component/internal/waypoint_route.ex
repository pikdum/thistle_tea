defmodule ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute do
  @moduledoc """
  A mob's waypoint patrol route built from `creature_movement` rows, tracking
  the current destination point and advancing through the loop.
  """
  alias ThistleTea.DB.Mangos.Creature
  alias ThistleTea.DB.Mangos.CreatureMovement
  alias ThistleTea.Game.Entity.Data.Component.Internal.Waypoint

  defstruct first_point: 0,
            destination_point: 0,
            points: %{},
            repeat?: true

  def build(%Creature{creature_movement: []}), do: nil
  def build(%Creature{creature_movement: nil}), do: nil

  def build(%Creature{position_x: x, position_y: y, position_z: z, creature_movement: creature_movement} = creature) do
    route = build_rows(creature_movement, creature.movement_scripts)
    closest_point = CreatureMovement.closest_point(creature_movement, {x, y, z})
    %{route | destination_point: closest_point}
  end

  def build_rows(rows, scripts_by_id) when is_list(rows) and rows != [] and is_map(scripts_by_id) do
    points =
      Map.new(rows, fn row ->
        {row.point,
         %Waypoint{
           position: {row.position_x, row.position_y, row.position_z, orientation(row.orientation)},
           wait_time: row.waittime,
           script_steps: Map.get(scripts_by_id, row.script_id, [])
         }}
      end)

    first_point = rows |> Enum.map(& &1.point) |> Enum.min()

    %__MODULE__{
      first_point: first_point,
      destination_point: first_point,
      points: points
    }
  end

  def start(%__MODULE__{} = route, start_point, repeat?) when is_boolean(repeat?) do
    destination_point =
      if is_integer(start_point) and start_point > 0 and Map.has_key?(route.points, start_point) do
        start_point
      else
        route.first_point
      end

    %{route | destination_point: destination_point, repeat?: repeat?}
  end

  def destination_waypoint(%__MODULE__{destination_point: id, points: points}) do
    Map.get(points, id)
  end

  def increment_waypoint(%__MODULE__{first_point: first_point, destination_point: id, points: points} = route) do
    next_id = points |> Map.keys() |> Enum.filter(&(&1 > id)) |> Enum.min(fn -> nil end)
    next_id = next_id || if(route.repeat?, do: first_point)

    %{route | destination_point: next_id}
  end

  defp orientation(100.0), do: nil
  defp orientation(orientation), do: orientation
end
