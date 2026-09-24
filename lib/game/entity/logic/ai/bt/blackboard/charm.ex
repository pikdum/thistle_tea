defmodule ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Charm do
  @moduledoc false
  defstruct [:next_cast_at, :next_move_at, melee_fallback?: false]
end
