defmodule ThistleTea.Game.Entity.Data.Component.Internal.Spawn do
  @moduledoc """
  A mob's spawn-point snapshot and respawn state: the unit and movement block
  to restore on respawn, the home position with wander/waypoint movement
  config, and the pending respawn timer.
  """
  defstruct [
    :unit,
    :movement_block,
    :position,
    :distance,
    :movement_type,
    :waypoint_route,
    :respawn_delay_ms,
    :respawn_ref,
    respawn_pending?: false
  ]
end
