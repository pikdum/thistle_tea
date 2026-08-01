defmodule ThistleTea.Game.World.Position.ClientMotion do
  @moduledoc false

  @enforce_keys [:world, :origin, :velocity, :started_at, :expires_at]
  defstruct [:world, :origin, :velocity, :started_at, :expires_at]
end
