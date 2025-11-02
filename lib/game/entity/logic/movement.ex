defmodule ThistleTea.Game.Entity.Logic.Movement do
  use ThistleTea.Game.Network.Opcodes, [:SMSG_MONSTER_MOVE]

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Waypoint
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgMonsterMove
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Util

  @max_u32 0xFFFFFFFF

  def increment_spline_id(%{internal: %Internal{spline_id: spline_id} = internal} = entity) do
    new_spline_id = increment_spline_id(spline_id)
    %{entity | internal: %{internal | spline_id: new_spline_id}}
  end

  def increment_spline_id(id) when is_integer(id) do
    rem(id, @max_u32) + 1
  end

  def start_move_to(
        %{
          movement_block: %MovementBlock{walk_speed: walk_speed, position: {x0, y0, z0, _o}} = mb,
          internal: %Internal{map: map}
        } = entity,
        {x, y, z}
      ) do
    path = Pathfinding.find_path(map, {x0, y0, z0}, {x, y, z})

    if is_nil(path) do
      # handles maps that haven't been built yet
      raise "No path found from #{inspect({x0, y0, z0})} to #{inspect({x, y, z})}"
    end

    # TODO handle running and walking
    duration =
      [{x0, y0, z0} | path]
      |> Util.movement_duration(walk_speed)
      |> Kernel.*(1_000)
      |> trunc()
      |> max(1)

    # TODO how does it use time_passed when sent in an update packet?
    # likely need to store when movement started?
    %{entity | movement_block: %{mb | spline_nodes: path, duration: duration, time_passed: 0, spline_flags: 0x100}}
    |> increment_spline_id()
  end

  def move_to(state, {x, y, z}) do
    state = start_move_to(state, {x, y, z})
    packet = Message.to_packet(SmsgMonsterMove.build(state))

    # TODO: how do i want to handle updating the position on the server side?
    # sounds like vmangos does this every 100ms
    # i could instead do it whenever position is requested?
    # or a timer at the end of the movement duration?
    {_, _, _, o} = state.movement_block.position
    {xd, yd, zd} = List.last(state.movement_block.spline_nodes)

    nearby_players = Core.nearby_players(state)

    # TODO: could be done in handle_continue instead?
    # or at least abstracted to a separate function
    for {_guid, pid, _distance} <- nearby_players do
      GenServer.cast(pid, {:send_packet, packet.opcode, packet.payload})
    end

    %{state | movement_block: %{state.movement_block | position: {xd, yd, zd, o}}}
  end

  def wander(%{internal: %Internal{spawn_distance: spawn_distance, map: map, initial_position: {xi, yi, zi}}} = state) do
    case Pathfinding.find_random_point_around_circle(map, {xi, yi, zi}, spawn_distance) do
      nil -> state
      {x, y, z} -> move_to(state, {x, y, z})
    end
  end

  def wander_delay(%{movement_block: %MovementBlock{duration: duration}}) do
    duration = duration || 0
    duration + :rand.uniform(6_000) + 4_000
  end

  def follow_waypoint_route(%{internal: %Internal{waypoint_route: %WaypointRoute{} = route}} = state) do
    %Waypoint{position: {x, y, z, o}} = WaypointRoute.destination_waypoint(route)

    state
    |> move_to({x, y, z})
    |> set_orientation(o)
    |> increment_waypoint()
  end

  def follow_waypoint_route_delay(%{
        movement_block: %MovementBlock{duration: duration},
        internal: %Internal{waypoint_route: route}
      }) do
    duration = duration || 0
    wait_time = WaypointRoute.destination_waypoint(route).wait_time || 0
    duration + wait_time
  end

  defp increment_waypoint(%{internal: %Internal{waypoint_route: route} = internal} = state) do
    route = WaypointRoute.increment_waypoint(route)
    %{state | internal: %{internal | waypoint_route: route}}
  end

  defp set_orientation(%{movement_block: %MovementBlock{position: {x, y, z, _o}}} = entity, o) do
    %{entity | movement_block: %{entity.movement_block | position: {x, y, z, o}}}
  end
end
