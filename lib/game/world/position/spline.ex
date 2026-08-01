defmodule ThistleTea.Game.World.Position.Spline do
  @moduledoc false

  @enforce_keys [:world, :origin, :nodes, :started_at, :duration_ms]
  defstruct [:world, :origin, :nodes, :started_at, :duration_ms]
end
