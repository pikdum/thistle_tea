defmodule ThistleTea.Game.Entity.Logic.AI.BT.Flee do
  @moduledoc """
  Timed fleeing shared by scripted creatures and critters, using the same
  panic movement as spell fear with an independent deadline and memory.
  """

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Fear, as: FearMemory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.FleeMovement
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Fear
  alias ThistleTea.Game.Entity.Logic.Movement

  def tick(%Mob{} = mob, %Blackboard{combat: %{flee_until: until}} = blackboard, %Context{now: now} = context)
      when is_integer(until) do
    cond do
      now >= until or mob.unit.health <= 0 ->
        clear(mob, blackboard)

      Fear.blocked?(mob) or Aura.has_aura?(mob, :prevent_fleeing) ->
        {mob, events} = Movement.stop_with_effects(mob, now)
        {BT.running(min(500, until - now), :flee), Effects.enqueue(mob, events), blackboard}

      true ->
        move(mob, blackboard, context)
    end
  end

  def tick(mob, blackboard, _context), do: {:failure, mob, blackboard}

  defp clear(mob, blackboard) do
    blackboard = Blackboard.clear_flee(blackboard)
    mob = %{mob | internal: %{mob.internal | blackboard: blackboard, broadcast_update?: true}}
    {:failure, ControlMovement.sync_flags(mob), blackboard}
  end

  defp move(mob, blackboard, %Context{now: now} = context) do
    memory = blackboard.flee || %FearMemory{next_move_at: now, previous_running: mob.internal.running}
    {{:running, delay, reason}, mob, memory} = FleeMovement.tick(mob, memory, context)
    reason = if reason == :fear, do: :flee, else: reason
    status = BT.running(min(delay, blackboard.combat.flee_until - now), reason)
    {status, mob, %{blackboard | flee: memory}}
  end
end
