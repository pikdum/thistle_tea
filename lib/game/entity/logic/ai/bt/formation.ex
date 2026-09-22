defmodule ThistleTea.Game.Entity.Logic.AI.BT.Formation do
  @moduledoc """
  Follows the leader's current path endpoint at a formation offset. Patrol
  ownership and inherited waypoint cursors remain separate from combat movement.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Formation, as: Membership
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Formation, as: Memory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Formation, as: Snapshot
  alias ThistleTea.Game.Entity.Logic.AI.BT.Navigation
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.CreatureFlags
  alias ThistleTea.Game.Entity.Logic.CreatureGroup.Member
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Math

  @tick_ms 200
  @teleport_distance 100.0

  def sync(%Mob{} = state, %Blackboard{} = blackboard, %Context{formation: snapshot, now: now}) do
    membership = if snapshot, do: snapshot.membership
    identity = identity(membership)

    if identity == memory_identity(blackboard.formation) do
      {:failure, state, blackboard}
    else
      stop? = reset_movement?(state, blackboard, membership)
      state = if stop?, do: Movement.stop(state, now), else: state
      blackboard = if stop?, do: Blackboard.clear_waypoint(blackboard), else: blackboard
      memory = memory(membership)
      blackboard = %{blackboard | formation: memory}

      blackboard =
        if memory && memory.route,
          do: Blackboard.put_next_at(blackboard, :next_waypoint_at, 1_000, now),
          else: blackboard

      {:failure, state, blackboard}
    end
  end

  def tick(
        %Mob{} = state,
        %Blackboard{} = blackboard,
        %Context{formation: %Snapshot{membership: %Membership{role: :follower}} = snapshot, now: now} = context
      ) do
    cond do
      not idle?(state, blackboard) or CreatureFlags.has?(state, :sessile) or state.internal.rooted? == true ->
        wait(state, blackboard)

      Movement.moving?(state, now) ->
        wait(state, blackboard)

      not snapshot.leader_ready? ->
        wait(state, blackboard)

      not active_path?(snapshot, now) ->
        wait(state, blackboard)

      distance_to_leader(state, snapshot) >= @teleport_distance ->
        teleport_to_leader(state, blackboard, snapshot, now)

      true ->
        follow_path(state, blackboard, snapshot, context)
    end
  end

  def tick(state, blackboard, _context), do: {:failure, state, blackboard}

  def home_position(%Context{
        formation: %Snapshot{
          membership: %Membership{role: :follower, member: %Member{} = member},
          leader_position: {_world, x, y, z},
          leader_orientation: angle
        }
      })
      when is_number(angle) do
    offset({x, y, z}, angle, member)
  end

  def home_position(%Context{formation: %Snapshot{membership: %Membership{role: :leader, home_position: position}}}) do
    position
  end

  def home_position(_context), do: nil

  def offset({x, y, z}, angle, %Member{distance: distance, angle: offset}) do
    {x + :math.cos(angle + offset) * distance, y + :math.sin(angle + offset) * distance, z}
  end

  defp identity(%Membership{token: token, leader_guid: leader, role: role}), do: {token, leader, role}
  defp identity(nil), do: nil
  defp memory_identity(%Memory{identity: identity}), do: identity
  defp memory_identity(nil), do: nil
  defp follower?(%Membership{role: :follower}), do: true
  defp follower?(_membership), do: false

  defp reset_movement?(state, blackboard, membership) do
    idle?(state, blackboard) and not blackboard.navigation.returning_home? and
      (follower?(membership) or blackboard.formation != nil)
  end

  defp memory(%Membership{} = membership) do
    route = if membership.route, do: WaypointRoute.start(membership.route, membership.last_waypoint, true)
    %Memory{identity: identity(membership), role: membership.role, route: route}
  end

  defp memory(nil), do: nil

  defp idle?(state, blackboard) do
    not Core.dead?(state) and state.internal.in_combat != true and blackboard.fear == nil and
      blackboard.confusion == nil and blackboard.flee == nil
  end

  defp active_path?(%Snapshot{path: [_ | [_ | _]], arrives_at: deadline}, now),
    do: is_integer(deadline) and deadline > now

  defp active_path?(_snapshot, _now), do: false

  defp distance_to_leader(state, %Snapshot{leader_position: {_world, x, y, z}}),
    do: Math.distance(position(state), {x, y, z})

  defp position(%Mob{movement_block: %{position: {x, y, z, _}}}), do: {x, y, z}

  defp follow_path(
         state,
         blackboard,
         %Snapshot{path: path, membership: %{member: %Member{} = member}} = snapshot,
         context
       ) do
    destination = List.last(path)
    previous = path |> Enum.reverse() |> Enum.find(&(&1 != destination))

    if previous do
      {x, y, _z} = destination
      {px, py, _pz} = previous
      angle = :math.atan2(y - py, x - px)
      destination = offset(destination, angle, member)

      if Math.distance(position(state), destination) >= 0.2 do
        opts = [
          face_angle: angle,
          arrive_at: snapshot.arrives_at,
          max_velocity: state.movement_block.run_speed * 1.3,
          run?: Blackboard.run_mode?(blackboard)
        ]

        state = Navigation.move_to(state, destination, opts, context)

        memory = %{
          blackboard.formation
          | destination: destination,
            leader_path: snapshot.started_at,
            spline_id: Movement.increment_spline_id(state.internal.spline_id)
        }

        blackboard = %{blackboard | formation: memory, navigation: %{blackboard.navigation | move_target: destination}}
        wait(state, blackboard)
      else
        wait(state, blackboard)
      end
    else
      wait(state, blackboard)
    end
  end

  defp teleport_to_leader(
         state,
         blackboard,
         %Snapshot{leader_position: {_world, x, y, z}, leader_orientation: orientation},
         now
       ) do
    {state, transition} = Movement.teleport(state, {x, y, z, orientation || 0.0}, now)

    effect =
      Effects.creature_teleported(
        state.internal.world,
        transition.from_position,
        transition.position,
        transition.movement_block,
        0,
        state.internal.world.map_id,
        0
      )

    wait(Effects.enqueue(state, effect), Blackboard.clear_move_target(blackboard))
  end

  defp wait(state, blackboard), do: {BT.running(@tick_ms, :formation), state, blackboard}
end
