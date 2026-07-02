defmodule ThistleTea.Game.Entity.Data.Component.Internal.Spawn do
  @moduledoc """
  A mob's spawn-point snapshot and respawn state: the unit and movement block
  to restore on respawn, the home position with wander/waypoint movement
  config, and the pending respawn timer. Temporary summons carry their timed
  despawn config here and are stopped instead of respawned.
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
    :despawn_type,
    :despawn_delay_ms,
    temporary?: false,
    respawn_pending?: false
  ]
end
