defmodule ThistleTea.Game.Core.Entity.Component.Internal.Waypoint do
  @moduledoc false
  defstruct [:position, :wait_time, script_steps: []]
end
