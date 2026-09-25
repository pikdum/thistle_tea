defmodule ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.EventAI do
  @moduledoc false

  defmodule Actions do
    @moduledoc false
    defstruct [:token, :event_id, runs: MapSet.new(), failed?: false]
  end

  defstruct phase: 0, timers: nil, disabled: nil, next_at: 0, sequence: 0, pending: %{}
end
