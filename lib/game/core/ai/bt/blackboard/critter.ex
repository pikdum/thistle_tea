defmodule ThistleTea.Game.Core.AI.BT.Blackboard.Critter do
  @moduledoc false

  @enforce_keys [:escape_at, :previous_running]
  defstruct [:escape_at, :previous_running]
end
