defmodule ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Navigation do
  @moduledoc false

  defstruct target: nil,
            move_target: nil,
            orientation: nil,
            wait_time: nil,
            last_target_pos: nil,
            confused_anchor: nil,
            chase_started: false,
            run_mode: false,
            next_chase_at: 0,
            next_wander_at: 0,
            next_waypoint_at: 0,
            next_confused_at: 0
end
