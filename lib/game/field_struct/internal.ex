defmodule ThistleTea.Game.FieldStruct.Internal do
  defstruct [
    :map,
    :name,
    :spawn_distance,
    :movement_type,
    :initial_position,
    spline_id: 0
  ]
end
