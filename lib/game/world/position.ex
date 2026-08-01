defmodule ThistleTea.Game.World.Position do
  @moduledoc """
  Owns the stationary and projected position records for world entities.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.World.Position.ClientMotion
  alias ThistleTea.Game.World.Position.Spline
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
    reconcile_spline(entity)
  end

  def put(
        %{
          object: %{guid: guid},
          internal: %Internal{world: world},
          movement_block: %MovementBlock{position: {x, y, z, _orientation}}
        },
        table,
        projection
      )
      when is_integer(guid) and is_atom(table) and (is_struct(projection) or is_nil(projection)) do
    SpatialHash.update(table, guid, world, x, y, z)
    reconcile_projection(guid, projection)
  end

  def remove(%{object: %{guid: guid}}, table) when is_integer(guid) and is_atom(table) do
    SpatialHash.remove(table, guid)
  end

  def get(guid, now) when is_integer(guid) and is_integer(now) do
    case SpatialHash.get_projection(guid) do
      %Spline{} = projection ->
        {x, y, z} = spline_position(projection, now)
        {projection.world, x, y, z}

      %ClientMotion{} = projection ->
        {x, y, z} = client_position(projection, now)
        {projection.world, x, y, z}

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
    case SpatialHash.get_projection(guid) do
      %Spline{started_at: started_at, duration_ms: duration_ms} ->
        now <= started_at + duration_ms

      %ClientMotion{started_at: started_at, expires_at: expires_at} ->
        now >= started_at and now <= expires_at

      {_world, _start_position, spline_nodes, start_time, duration} ->
        spline_nodes != [] and now <= start_time + duration

      _ ->
        false
    end
  end

  def projection(guid) when is_integer(guid), do: SpatialHash.get_projection(guid)

  def client_motion(
        %{internal: %Internal{world: world}, movement_block: %MovementBlock{position: {x, y, z, _orientation}}},
        {vx, vy, vz},
        now,
        duration_ms
      )
      when is_number(vx) and is_number(vy) and is_number(vz) and is_integer(now) and is_integer(duration_ms) and
             duration_ms > 0 do
    if !(vx == 0.0 and vy == 0.0 and vz == 0.0) do
      %ClientMotion{
        world: WorldRef.coerce(world),
        origin: {x, y, z},
        velocity: {vx, vy, vz},
        started_at: now,
        expires_at: now + duration_ms
      }
    end
  end

  defp reconcile_spline(%{
         object: %{guid: guid},
         internal: %Internal{world: world, movement_start_time: start_time, movement_start_position: start_position},
         movement_block: %MovementBlock{spline_nodes: spline_nodes, duration: duration}
       })
       when is_integer(start_time) and is_tuple(start_position) and is_list(spline_nodes) and spline_nodes != [] and
              is_integer(duration) and duration > 0 do
    projection = %Spline{
      world: WorldRef.coerce(world),
      origin: start_position,
      nodes: spline_nodes,
      started_at: start_time,
      duration_ms: duration
    }

    SpatialHash.put_projection(guid, projection)
  end

  defp reconcile_spline(%{object: %{guid: guid}}) when is_integer(guid) do
    SpatialHash.clear_projection(guid)
  end

  defp reconcile_projection(guid, nil), do: SpatialHash.clear_projection(guid)
  defp reconcile_projection(guid, projection), do: SpatialHash.put_projection(guid, projection)

  defp spline_position(%Spline{} = projection, now) do
    Movement.position_at(
      projection.origin,
      projection.nodes,
      projection.duration_ms,
      now - projection.started_at
    )
  end

  defp client_position(%ClientMotion{} = projection, now) do
    elapsed_ms = min(max(now - projection.started_at, 0), projection.expires_at - projection.started_at)
    seconds = elapsed_ms / 1_000
    {x, y, z} = projection.origin
    {vx, vy, vz} = projection.velocity
    {x + vx * seconds, y + vy * seconds, z + vz * seconds}
  end
end
