defmodule ThistleTea.Game.Core.AI.BT.Blackboard.Confusion do
  @moduledoc false

  defstruct [:anchor, next_move_at: 0, moving?: false, previous_running: false]
end
