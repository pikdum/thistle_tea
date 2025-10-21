defmodule ThistleTea.Game.FieldStruct.Internal do
  defstruct [
    :map,
    :name,
    :spawn_distance,
    :movement_type,
    :initial_position,
    :waypoint_route,
    spline_id: 0
  ]
end
