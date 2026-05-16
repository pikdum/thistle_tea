defmodule ThistleTea.Game.Entity.Data.Component.Internal do
  defstruct [
    :map,
    :name,
    :area,
    :spells,
    :casting,
    :spawn_distance,
    :movement_type,
    :experience_multiplier,
    :extra_flags,
    :rank,
    :initial_position,
    :waypoint_route,
    :event,
    :in_combat,
    :last_hostile_time,
    :running,
    :behavior_tree,
    :blackboard,
    :movement_start_time,
    :movement_start_position,
    broadcast_update?: false,
    spline_id: 0
  ]
end
