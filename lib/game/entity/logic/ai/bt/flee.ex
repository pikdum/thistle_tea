defmodule ThistleTea.Game.Entity.Logic.AI.BT.Flee do
  @moduledoc """
  Timed fleeing shared by scripted creatures and critters, using the same
  panic movement as spell fear with an independent deadline and memory.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Assistance, as: AssistanceMemory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Fear, as: FearMemory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.FleeMovement
  alias ThistleTea.Game.Entity.Logic.Assistance
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Fear
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Spell.Cast

  @duration_ms 7_000
  @flee_text "%s attempts to run away in fear!"

  def duration_ms, do: @duration_ms

  def start(%Mob{unit: %{target: target, health: health}} = mob, blackboard, context, seek?)
      when is_integer(target) and target > 0 and health > 0 do
    if prevented?(mob, blackboard, context.now) do
      {mob, blackboard}
    else
      blackboard = blackboard |> Blackboard.clear_chase() |> Blackboard.clear_flee()
      blackboard = start_memory(mob, blackboard, context, seek?)
      {mob, events} = Movement.stop_with_effects(mob, context.now)

      mob =
        mob
        |> Effects.enqueue(events)
        |> Effects.enqueue(Effects.monster_talk(@flee_text, :text_emote, target))
        |> interrupt_movement_cast(context.now)

      mob = %{mob | internal: %{mob.internal | blackboard: blackboard, broadcast_update?: true}}
      {ControlMovement.sync_flags(mob), blackboard}
    end
  end

  def start(mob, blackboard, _context, _seek?), do: {mob, blackboard}

  defp prevented?(mob, blackboard, now) do
    distracted = blackboard.navigation.distracted_until

    Enum.any?([:prevent_fleeing, :feign_death, :mod_confuse], &Aura.has_aura?(mob, &1)) or
      match?(%{possessed?: true}, mob.internal.pet) or
      (is_integer(distracted) and distracted > now)
  end

  defp start_memory(mob, blackboard, context, seek?) do
    case seek? && Assistance.nearest(mob, context.perception) do
      {guid, destination} ->
        memory = %AssistanceMemory{
          helper_guid: guid,
          enemy_guid: mob.unit.target,
          destination: destination
        }

        %{blackboard | assistance: memory}

      _ ->
        memory = %FearMemory{next_move_at: context.now, previous_running: mob.internal.running}
        %{Blackboard.start_flee(blackboard, mob.unit.target, @duration_ms, context.now) | flee: memory}
    end
  end

  defp interrupt_movement_cast(%{internal: %{casting: %Cast{spell: spell}}} = mob, now) do
    if ((spell.interrupt_flags || 0) &&& 1) == 0, do: mob, else: Casting.interrupt(mob, now)
  end

  defp interrupt_movement_cast(mob, _now), do: mob

  def tick(%Mob{} = mob, %Blackboard{combat: %{flee_until: until}} = blackboard, %Context{now: now} = context)
      when is_integer(until) do
    cond do
      now >= until or mob.unit.health <= 0 ->
        clear(mob, blackboard, now)

      Fear.blocked?(mob) or Aura.has_aura?(mob, :prevent_fleeing) ->
        {mob, events} = Movement.stop_with_effects(mob, now)
        {BT.running(min(500, until - now), :flee), Effects.enqueue(mob, events), blackboard}

      true ->
        move(mob, blackboard, context)
    end
  end

  def tick(mob, blackboard, _context), do: {:failure, mob, blackboard}

  defp clear(mob, blackboard, now) do
    running = if blackboard.flee, do: blackboard.flee.previous_running, else: mob.internal.running
    {mob, events} = Movement.stop_with_effects(mob, now)
    blackboard = blackboard |> Blackboard.clear_flee() |> Blackboard.clear_chase()
    mob = Effects.enqueue(mob, events)
    mob = %{mob | internal: %{mob.internal | blackboard: blackboard, running: running, broadcast_update?: true}}
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
