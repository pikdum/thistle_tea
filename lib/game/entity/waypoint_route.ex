defmodule ThistleTea.Game.Entity.WaypointRoute do
  alias ThistleTea.DB.Mangos.Creature
  alias ThistleTea.DB.Mangos.CreatureMovement
  alias ThistleTea.Game.Entity.Waypoint

  defstruct first_point: 0,
            destination_point: 0,
            points: %{}

  def build(%Creature{creature_movement: []}), do: nil
  def build(%Creature{creature_movement: nil}), do: nil

  def build(%Creature{position_x: x, position_y: y, position_z: z, creature_movement: creature_movement}) do
    points =
      creature_movement
      |> Map.new(fn %CreatureMovement{} = cm ->
        {cm.point,
         %Waypoint{
           position: {cm.position_x, cm.position_y, cm.position_z, cm.orientation},
           wait_time: cm.waittime
         }}
      end)

    first_point = CreatureMovement.first_point(creature_movement)
    closest_point = CreatureMovement.closest_point(creature_movement, {x, y, z})

    %__MODULE__{
      first_point: first_point,
      destination_point: closest_point,
      points: points
    }
  end

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
