defmodule ThistleTea.Game.Entity.WaypointRoute do
  alias ThistleTea.Game.Entity.Waypoint

  defstruct first_point: 0,
            destination_point: 0,
            points: %{}

  def destination_waypoint(%__MODULE__{destination_point: id, points: points}) do
    Map.get(points, id)
  end

  def increment_waypoint(%__MODULE__{first_point: first_point, destination_point: id, points: points} = route) do
    next_id =
      case Map.get(points, id + 1) do
        nil -> first_point
        %Waypoint{} -> id + 1
      end

    %{route | destination_point: next_id}
  end
end
