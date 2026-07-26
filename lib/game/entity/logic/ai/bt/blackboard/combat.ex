defmodule ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Combat do
  @moduledoc false

  defstruct next_attack_at: 0,
            next_offhand_attack_at: 0,
            next_aggro_at: 0,
            next_call_for_help_at: 0,
            next_spread_at: 0,
            attack_started: false,
            auto_attacking: false,
            auto_attack_target: nil,
            spread_attempts: 0,
            spreading: false,
            flee_until: nil,
            flee_from: nil
end
