defmodule ThistleTea.Game.Core.AI.BT.Follow do
  @moduledoc """
  Keeps a creature at a distance and angle off its leader's facing. It
  repaths to the leader's predicted position only once that point has moved,
  settles beside a leader who has stopped, and runs faster the further it
  falls behind.

  Pets follow their owners with `step/5`. Other creatures follow whoever a
  movement script names (vmangos `FOLLOW_MOTION_TYPE`) through `tick/3`
  until another movement takes over. A scripted follower waits in place
  while its leader is out of sight or in another world.
  """

  alias ThistleTea.Game.Core.AI.BT
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Blackboard.Follow, as: FollowMemory
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Navigation
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Movement

  @start_distance 0.25
  @repath_distance 0.5
  @stationary_slack_factor 1.4
  @prediction_ms 500
  @tick_ms 100
  @lost_ms 500

  def tick_ms, do: @tick_ms

  def tick(%Mob{} = state, %Blackboard{} = blackboard, %Context{} = context) do
    case Blackboard.following(blackboard) do
      %FollowMemory{guid: leader, distance: distance, angle: angle} ->
        case step(state, leader, distance, angle, context) do
          {:ok, state} -> {BT.running(@tick_ms, :follow), state, blackboard}
          :lost -> {BT.running(@lost_ms, :follow), state, blackboard}
        end

      nil ->
        {:failure, state, blackboard}
    end
  end

  def tick(state, blackboard, %Context{}), do: {:failure, state, blackboard}

  def step(
        %Mob{internal: %Internal{world: world}} = state,
        leader,
        distance,
        angle,
        %Context{now: now, perception: perception} = context
      ) do
    with {^world, x, y, z} <- Perception.projected_position(perception, leader, @prediction_ms),
         %{orientation: orientation} when is_number(orientation) <- Perception.metadata(perception, leader) do
      destination = offset({x, y, z}, orientation + angle, distance)
      state = Movement.sync_position(state, now)

      if should_repath?(state, destination, distance, leader, {x, y, z}, context) do
        velocity = catchup_velocity(state, destination)

        state =
          state
          |> run()
          |> Navigation.follow(destination, orientation, velocity, context)
          |> face(orientation)

        {:ok, state}
      else
        {:ok, state}
      end
    else
      _ -> :lost
    end
  end

  defp offset({x, y, z}, angle, distance), do: {x + :math.cos(angle) * distance, y + :math.sin(angle) * distance, z}

  defp should_repath?(state, destination, distance, leader, leader_position, %Context{} = context) do
    not settled?(state, distance, leader, leader_position, context) and
      distance_to(state, destination) > @start_distance and
      destination_changed?(state.movement_block.spline_nodes, destination)
  end

  defp settled?(state, distance, leader, leader_position, %Context{now: now, perception: perception}) do
    not Perception.moving?(perception, leader) and not Movement.moving?(state, now) and
      distance_to(state, leader_position) <= stationary_slack(state, distance, leader, perception)
  end

  def stationary_slack(%Mob{unit: %Unit{bounding_radius: radius}}, distance, leader, perception) do
    @stationary_slack_factor * distance + bounding_radius(radius) + leader_bounding_radius(leader, perception)
  end

  defp leader_bounding_radius(leader, perception) do
    case Perception.metadata(perception, leader) do
      %{bounding_radius: radius} -> bounding_radius(radius)
      _ -> Unit.default_bounding_radius()
    end
  end

  defp bounding_radius(radius) when is_number(radius) and radius > 0, do: radius
  defp bounding_radius(_radius), do: Unit.default_bounding_radius()

  defp destination_changed?([_ | _] = nodes, destination) do
    point_distance(List.last(nodes), destination) > @repath_distance
  end

  defp destination_changed?(_nodes, _destination), do: true

  defp catchup_velocity(%Mob{movement_block: %{run_speed: speed}} = state, destination)
       when is_number(speed) and speed > 0 do
    distance = distance_to(state, destination)
    factor = if distance > speed, do: min(1.0 + 0.04 * (distance - speed), 2.1), else: 1.0
    speed * factor
  end

  defp catchup_velocity(_state, _destination), do: nil

  defp distance_to(%Mob{movement_block: %{position: {x, y, z, _o}}}, position), do: point_distance({x, y, z}, position)

  defp point_distance({x, y, z}, {tx, ty, tz}) do
    :math.sqrt(:math.pow(tx - x, 2) + :math.pow(ty - y, 2) + :math.pow(tz - z, 2))
  end

  defp run(%Mob{internal: %Internal{} = internal} = state), do: %{state | internal: %{internal | running: true}}

  defp face(%Mob{movement_block: %MovementBlock{position: {x, y, z, _o}} = movement_block} = state, orientation) do
    %{state | movement_block: %{movement_block | position: {x, y, z, orientation}}}
  end
end
