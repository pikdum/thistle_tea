defmodule ThistleTea.Game.World.Position do
  @moduledoc """
  Owns the stationary and projected position records for world entities.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  def put(
        %{
          object: %{guid: guid},
          internal: %Internal{world: world},
          movement_block: %MovementBlock{position: {x, y, z, _orientation}}
        } = entity,
        table
      )
      when is_integer(guid) and is_atom(table) do
    SpatialHash.update(table, guid, world, x, y, z)
    reconcile_projection(entity)
  end

  def remove(%{object: %{guid: guid}}, table) when is_integer(guid) and is_atom(table) do
    SpatialHash.remove(table, guid)
  end

  def get(guid, now) when is_integer(guid) and is_integer(now) do
    case SpatialHash.get_movement(guid) do
      {world, start_position, spline_nodes, start_time, duration} ->
        {x, y, z} = Movement.position_at(start_position, spline_nodes, duration, now - start_time)
        {world, x, y, z}

      nil ->
        case SpatialHash.get_entity(guid) do
          {^guid, world, x, y, z} -> {world, x, y, z}
          nil -> nil
        end
    end
  end

  def moving?(guid, now) when is_integer(guid) and is_integer(now) do
    case SpatialHash.get_movement(guid) do
      {_world, _start_position, spline_nodes, start_time, duration}
      when is_list(spline_nodes) and spline_nodes != [] and is_integer(start_time) and is_integer(duration) and
             duration > 0 ->
        now <= start_time + duration

      _ ->
        false
    end
  end

  def projection(guid) when is_integer(guid), do: SpatialHash.get_movement(guid)

  defp reconcile_projection(%{
         object: %{guid: guid},
         internal: %Internal{world: world, movement_start_time: start_time, movement_start_position: start_position},
         movement_block: %MovementBlock{spline_nodes: spline_nodes, duration: duration}
       })
       when is_integer(start_time) and is_tuple(start_position) and is_list(spline_nodes) and spline_nodes != [] and
              is_integer(duration) and duration > 0 do
    SpatialHash.put_movement(guid, {WorldRef.coerce(world), start_position, spline_nodes, start_time, duration})
  end

  defp reconcile_projection(%{object: %{guid: guid}}) when is_integer(guid) do
    SpatialHash.clear_movement(guid)
  end
end
