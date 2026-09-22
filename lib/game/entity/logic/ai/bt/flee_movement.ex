defmodule ThistleTea.Game.Entity.Logic.AI.BT.FleeMovement do
  @moduledoc """
  Shared panic runs and pauses for spell fear and timed fleeing. Destinations
  come from the owner's terrain observations, with bounded paths.
  """

  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Fear, as: FearMemory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Navigation
  alias ThistleTea.Game.Entity.Logic.Fear
  alias ThistleTea.Game.Entity.Logic.Movement

  def tick(mob, %FearMemory{} = memory, %Context{now: now} = context) do
    cond do
      Fear.blocked?(mob) ->
        {BT.running(500, :fear), mob, memory}

      Movement.moving?(mob, now) ->
        {BT.running(Movement.next_spatial_update_delay(mob, now), :movement), mob, memory}

      memory.moving? ->
        pause(mob, memory, context, 800, 1_500)

      now < memory.next_move_at ->
        {BT.running(memory.next_move_at - now, :fear), mob, memory}

      true ->
        move(mob, memory, context)
    end
  end

  defp move(mob, memory, %Context{navigation: %{fear_point: nil}} = context) do
    pause(mob, memory, context, 1_000, 1_500)
  end

  defp move(mob, memory, %Context{navigation: %{fear_point: destination}} = context) do
    mob = %{mob | internal: %{mob.internal | running: true}}
    mob = Navigation.move_to(mob, destination, [allow_steep: false, max_distance: 30.0], context)
    {BT.running(0, :navigation), mob, %{memory | moving?: true}}
  end

  defp pause(mob, memory, %Context{now: now, random: random}, minimum, maximum) do
    delay = Random.between(random, minimum, maximum)
    {BT.running(delay, :fear), mob, %{memory | moving?: false, next_move_at: now + delay}}
  end
end
