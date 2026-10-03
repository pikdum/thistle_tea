defmodule ThistleTea.Game.Core.AI.CreatureScript.Route do
  @moduledoc """
  A path a `Core.AI.CreatureScript` port walks, with the steps to run at each
  of its points. The path is the creature's `script_waypoint` rows, or its
  own `path` of `{x, y, z, wait_ms}` points when vmangos keeps them in C++.
  A creature with several paths tells them apart by `variant`, which
  `start_waypoints` source 5 reads from `dataint3`.
  """

  @enforce_keys [:entry]
  defstruct [:entry, :path, variant: 0, points: %{}]

  def key(%__MODULE__{entry: entry, variant: variant}), do: {:script, entry, variant}
end
