defmodule ThistleTea.Game.Entity.Logic.AI.BT.Fear do
  @moduledoc """
  Runs frightened creatures using navigation observations supplied by their
  owner. Each completed run is followed by a pause before choosing a new run.
  """

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Fear, as: FearMemory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Navigation
  alias ThistleTea.Game.Entity.Logic.Fear
  alias ThistleTea.Game.Entity.Logic.Movement

  def tick(%Mob{} = mob, %Blackboard{} = blackboard, %Context{} = context) do
    if Fear.active?(mob) do
      memory = blackboard.fear || %FearMemory{previous_running: mob.internal.running}
      run(mob, %{blackboard | fear: memory}, context)
    else
      {:failure, mob, blackboard}
    end
  end

  def tick(entity, blackboard, _context), do: {:failure, entity, blackboard}

  defp run(mob, %Blackboard{fear: memory} = blackboard, %Context{now: now} = context) do
    cond do
      Fear.blocked?(mob) ->
        {BT.running(500, :fear), mob, blackboard}

      Movement.moving?(mob, now) ->
        Navigation.wait_for_arrival(mob, blackboard, context)

      memory.moving? ->
        pause(mob, blackboard, context, 800, 1_500)

      now < memory.next_move_at ->
        {BT.running(memory.next_move_at - now, :fear), mob, blackboard}

      true ->
        move(mob, blackboard, context)
    end
  end

  defp move(mob, blackboard, %Context{navigation: %{fear_point: nil}} = context) do
    pause(mob, blackboard, context, 1_000, 1_500)
  end

  defp move(mob, %Blackboard{fear: memory} = blackboard, %Context{navigation: %{fear_point: destination}} = context) do
    mob = %{mob | internal: %{mob.internal | running: true}}
    mob = Navigation.move_to(mob, destination, [allow_steep: false, max_distance: 30.0], context)
    blackboard = %{blackboard | fear: %{memory | moving?: true}}
    {BT.running(0, :navigation), mob, blackboard}
  end

  defp pause(mob, %Blackboard{fear: memory} = blackboard, %Context{now: now, random: random}, minimum, maximum) do
    delay = Random.between(random, minimum, maximum)
    blackboard = %{blackboard | fear: %{memory | moving?: false, next_move_at: now + delay}}
    {BT.running(delay, :fear), mob, blackboard}
  end
end
