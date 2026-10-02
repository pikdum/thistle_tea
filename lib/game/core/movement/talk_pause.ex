defmodule ThistleTea.Game.Core.Movement.TalkPause do
  @moduledoc """
  vmangos `Creature::PauseOutOfCombatMovement`: a player greeting a creature or
  choosing one of its gossip options stops it wandering or patrolling for three
  minutes, so it does not walk off while their window is open.

  The pause only ever pushes back the creature's next wander or waypoint step,
  the way vmangos `AddPauseTime` does, so a script that sets new movement
  replaces it. Creatures that are fighting, dead, flying, mid scripted move, or
  flagged to keep moving (extra flag 0x20) ignore it.
  """

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.Creature.CreatureFlags
  alias ThistleTea.Game.Core.Creature.CreatureMovement
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Movement

  @pause_ms 180_000

  def pause_ms, do: @pause_ms

  def apply(%Mob{internal: internal} = mob, now) when is_integer(now) do
    blackboard = Blackboard.ensure(internal.blackboard)

    case pausable_motion(mob, blackboard, now) do
      nil ->
        {mob, []}

      motion ->
        {mob, events} = Movement.stop_with_effects(mob, now)
        blackboard = Blackboard.pause_idle_movement(blackboard, motion, now + @pause_ms)
        {%{mob | internal: %{mob.internal | blackboard: blackboard}}, events}
    end
  end

  def apply(entity, _now), do: {entity, []}

  defp pausable_motion(mob, blackboard, now) do
    if !(Entity.dead?(mob) or mob.internal.in_combat == true or CreatureFlags.no_movement_pause?(mob) or
           CreatureMovement.flying?(mob) or scripted_move?(mob, blackboard, now)),
       do: motion(mob, blackboard)
  end

  defp scripted_move?(mob, blackboard, now) do
    Enum.any?(mob.internal.navigation_intents, &Keyword.has_key?(&1.opts, :movement_inform)) or
      (Movement.moving?(mob, now) and is_nil(blackboard.navigation.move_target))
  end

  defp motion(_mob, %Blackboard{navigation: %{returning_home?: true}}), do: nil
  defp motion(_mob, %Blackboard{navigation: %{movement_override: :random}}), do: :wander

  defp motion(_mob, %Blackboard{navigation: %{movement_override: :waypoint, scripted_waypoint_route: route}}),
    do: patrol(route)

  defp motion(_mob, %Blackboard{navigation: %{movement_override: override}}) when not is_nil(override), do: nil

  defp motion(%Mob{internal: %{spawn: %Spawn{waypoint_route: %WaypointRoute{} = route}}}, _blackboard),
    do: patrol(route)

  defp motion(%Mob{internal: %{spawn: %Spawn{movement_type: 1}}}, _blackboard), do: :wander
  defp motion(_mob, _blackboard), do: nil

  defp patrol(%WaypointRoute{cyclic?: false}), do: :waypoint
  defp patrol(_route), do: nil
end
