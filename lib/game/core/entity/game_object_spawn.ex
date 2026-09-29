defmodule ThistleTea.Game.Core.Entity.GameObjectSpawn do
  @moduledoc """
  One placed game object: its spawn id, template entry, map, position,
  rotation quaternion, initial state and animation, respawn delay, and the
  game event that gates it. `GameObject.build/2` pairs it with its template.
  """

  defstruct [
    :guid,
    :entry,
    :map_id,
    :respawn_seconds,
    :event,
    position: {0.0, 0.0, 0.0, 0.0},
    rotation: {0.0, 0.0, 0.0, 0.0},
    state: 0,
    anim_progress: 0
  ]
end
