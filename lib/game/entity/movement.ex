defmodule ThistleTea.Game.Entity.Movement do
  alias ThistleTea.Game.FieldStruct
  alias ThistleTea.Util

  @max_u32 0xFFFFFFFF

  def increment_spline_id(%{internal: %FieldStruct.Internal{spline_id: spline_id} = internal} = entity) do
    new_spline_id = increment_spline_id(spline_id)
    %{entity | internal: %{internal | spline_id: new_spline_id}}
  end

  def increment_spline_id(id) when is_integer(id) do
    rem(id, @max_u32) + 1
  end

  def start_move_to(%{movement_block: %FieldStruct.MovementBlock{run_speed: run_speed} = mb} = entity, {x, y, z}) do
    {x0, y0, z0, _o} = entity.movement_block.position
    map = entity.internal.map

    path = ThistleTea.Pathfinding.find_path(map, {x0, y0, z0}, {x, y, z})

    duration =
      [{x0, y0, z0} | path]
      |> Util.calculate_total_duration(run_speed * 7.0)
      |> trunc()
      |> max(1)

    # TODO how does it use time_passed when sent in an update packet?
    %{entity | movement_block: %{mb | spline_nodes: path, duration: duration, time_passed: 0, spline_flags: 0x100}}
    |> increment_spline_id()
  end
end
