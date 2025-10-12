defmodule ThistleTea.Game.Entity.Movement do
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.FieldStruct
  alias ThistleTea.Game.Message.SmsgMonsterMove
  alias ThistleTea.Util

  @smsg_monster_move 0x0DD
  @max_u32 0xFFFFFFFF

  def increment_spline_id(%{internal: %FieldStruct.Internal{spline_id: spline_id} = internal} = entity) do
    new_spline_id = increment_spline_id(spline_id)
    %{entity | internal: %{internal | spline_id: new_spline_id}}
  end

  def increment_spline_id(id) when is_integer(id) do
    rem(id, @max_u32) + 1
  end

  def start_move_to(
        %{
          movement_block: %FieldStruct.MovementBlock{walk_speed: walk_speed, position: {x0, y0, z0, _o}} = mb,
          internal: %FieldStruct.Internal{map: map}
        } = entity,
        {x, y, z}
      ) do
    path = ThistleTea.Pathfinding.find_path(map, {x0, y0, z0}, {x, y, z})

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
    payload = SmsgMonsterMove.build(state) |> SmsgMonsterMove.to_binary()

    # TODO: how do i want to handle updating the position on the server side?
    # sounds like vmangos does this every 100ms
    # i could instead do it whenever position is requested?
    # or a timer at the end of the movement duration?
    {_, _, _, o} = state.movement_block.position
    {xd, yd, zd} = List.last(state.movement_block.spline_nodes)

    nearby_players = Entity.Core.nearby_players(state)

    # TODO: i should come up with a packet struct that takes opcode as atom, payload as binary
    # and then use that as the interface instead of raw binaries
    # TODO: would also be nice to treat these like a side effect - can i use handle_continue or similar?
    for {_guid, pid, _distance} <- nearby_players do
      GenServer.cast(pid, {:send_packet, @smsg_monster_move, payload})
    end

    %{state | movement_block: %{state.movement_block | position: {xd, yd, zd, o}}}
  end

  def wander(
        %{
          movement_block: %FieldStruct.MovementBlock{position: {x0, y0, z0, _o}},
          internal: %FieldStruct.Internal{spawn_distance: spawn_distance, map: map}
        } = state
      ) do
    case ThistleTea.Pathfinding.find_random_point_around_circle(map, {x0, y0, z0}, spawn_distance) do
      nil -> state
      {x, y, z} -> move_to(state, {x, y, z})
    end
  end
end
