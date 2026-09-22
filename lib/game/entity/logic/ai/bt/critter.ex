defmodule ThistleTea.Game.Entity.Logic.AI.BT.Critter do
  @moduledoc """
  Keeps frightened critters from selecting victims or retaliating. A finished
  flee waits for the combat escape deadline, which later hits can extend.
  """

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Flee
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Movement

  def tick(%Mob{internal: %{in_combat: true}} = mob, blackboard, %Context{} = context) do
    if Mob.critter?(mob) do
      flee(mob, blackboard, context)
    else
      {:failure, mob, blackboard}
    end
  end

  def tick(mob, blackboard, _context), do: {:failure, mob, blackboard}

  defp flee(mob, blackboard, %Context{now: now} = context) do
    case Flee.tick(mob, blackboard, context) do
      {:failure, mob, blackboard} ->
        {mob, events} = Movement.stop_with_effects(mob, now)
        delay = if blackboard.critter, do: min(1_000, max(blackboard.critter.escape_at - now, 1)), else: 1
        {BT.running(delay, :critter_escape), Effects.enqueue(mob, events), blackboard}

      result ->
        result
    end
  end
end
