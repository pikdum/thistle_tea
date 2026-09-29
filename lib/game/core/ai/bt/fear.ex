defmodule ThistleTea.Game.Core.AI.BT.Fear do
  @moduledoc """
  Runs aura-frightened entities through shared fleeing movement.
  """

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Blackboard.Fear, as: FearMemory
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.FleeMovement
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Movement.ControlMovement

  def tick(%{unit: %Unit{}, internal: %Internal{}} = mob, %Blackboard{} = blackboard, %Context{} = context) do
    if ControlMovement.mode(mob) == :fear do
      memory = blackboard.fear || %FearMemory{next_move_at: context.now, previous_running: mob.internal.running}
      {status, mob, memory} = FleeMovement.tick(mob, memory, context)
      {status, mob, %{blackboard | fear: memory}}
    else
      {:failure, mob, blackboard}
    end
  end

  def tick(entity, blackboard, _context), do: {:failure, entity, blackboard}
end
