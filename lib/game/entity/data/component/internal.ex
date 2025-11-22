defmodule ThistleTea.Game.Entity.Data.Component.Internal do
  defstruct [
    :map,
    :name,
    :area,
    :spells,
    :spawn_distance,
    :movement_type,
    :initial_position,
    :waypoint_route,
    :event,
    spline_id: 0
  ]
end
