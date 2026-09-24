defmodule ThistleTea.Game.Entity.Logic.AI.BT.Patrol do
  @moduledoc "Drives continuous authored patrols and idle flight circles through navigation intents."

  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.CreatureFlags
  alias ThistleTea.Game.Entity.Logic.CreatureMovement
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Math

  @retry_ms 1_000

  def circle(entity, %Blackboard{} = blackboard, %Context{} = context, anchor, radius, wakes) do
    if CreatureMovement.flying?(entity) do
      advance(entity, blackboard, context, wakes, fn entity, blackboard ->
        path = CreatureMovement.circle(anchor, radius, position(entity))
        request_path(entity, blackboard, path, run?: true, flying?: true)
      end)
    else
      {:failure, entity, blackboard}
    end
  end

  def cycle(entity, blackboard, context, %WaypointRoute{cyclic?: true} = route, wakes) do
    advance(entity, blackboard, context, wakes, &request_cycle(&1, &2, route))
  end

  def cycle(entity, blackboard, _context, _route, _wakes), do: {:failure, entity, blackboard}

  defp request_cycle(entity, blackboard, route) do
    case WaypointRoute.cycle_points(route) do
      [first | _] = path ->
        opts = [run?: CreatureMovement.always_run?(entity) or Blackboard.run_mode?(blackboard)]

        if Math.distance(position(entity), first) > 10.0,
          do: request_approach(entity, blackboard, first, opts),
          else: request_path(entity, blackboard, path, opts)

      [] ->
        {BT.running(@retry_ms, :patrol), entity, blackboard}
    end
  end

  defp advance(entity, blackboard, %Context{now: now} = context, wakes, request) do
    cond do
      Movement.blocked?(entity) or CreatureFlags.has?(entity, :sessile) ->
        {BT.running(@retry_ms, :blocked), entity, blackboard}

      Movement.moving?(entity, now) or NavigationIntent.pending?(entity) ->
        Navigation.wait_for_arrival(entity, blackboard, context, wakes)

      true ->
        request.(entity, blackboard)
    end
  end

  defp request_path(entity, blackboard, [], _opts), do: {BT.running(@retry_ms, :patrol), entity, blackboard}

  defp request_path(entity, blackboard, path, opts) do
    entity = NavigationIntent.enqueue_path(entity, path, opts)
    {BT.running(0, :navigation), entity, mark_target(blackboard, List.last(path))}
  end

  defp request_approach(entity, blackboard, point, opts) do
    entity = NavigationIntent.enqueue(entity, point, opts)
    {BT.running(@retry_ms, :navigation), entity, mark_target(blackboard, point)}
  end

  defp mark_target(%Blackboard{navigation: navigation} = blackboard, point),
    do: %{blackboard | navigation: %{navigation | move_target: point}}

  defp position(%{movement_block: %{position: {x, y, z, _}}}), do: {x, y, z}
end
