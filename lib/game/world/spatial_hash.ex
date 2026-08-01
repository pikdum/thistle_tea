defmodule ThistleTea.Game.World.SpatialHash do
  @moduledoc """
  ETS-backed spatial hash with 125-yard cells per entity table, plus active
  spline-movement records, powering range queries and visibility cells.
  """
  alias ThistleTea.Game.SpatialGrid
  alias ThistleTea.Game.WorldRef

  @cell_table_options [:named_table, :public, :duplicate_bag, read_concurrency: true, write_concurrency: :auto]
  @entity_table_options [:named_table, :public, :set, read_concurrency: true, write_concurrency: :auto]

  def setup_tables do
    :ets.new(:players, @cell_table_options)
    :ets.new(:mobs, @cell_table_options)
    :ets.new(:game_objects, @cell_table_options)
    :ets.new(:corpses, @cell_table_options)
    :ets.new(:dynamic_objects, @cell_table_options)
    :ets.new(:entities, @entity_table_options)
    :ets.new(:entity_movement, @entity_table_options)
  end

  def put_projection(guid, projection) when is_integer(guid) and is_struct(projection) do
    :ets.insert(:entity_movement, {guid, projection})
  end

  def clear_projection(guid) do
    :ets.delete(:entity_movement, guid)
  end

  def get_projection(guid) do
    case :ets.lookup(:entity_movement, guid) do
      [{^guid, projection}] -> projection
      [] -> nil
    end
  end

  def insert(table, guid, world, x, y, z) do
    world = WorldRef.coerce(world)
    hash = cell(world, x, y, z)
    :ets.insert(table, {hash, guid})
    :ets.insert(:entities, {guid, world, x, y, z})
  end

  def update(table, guid, new_world, new_x, new_y, new_z) do
    new_world = WorldRef.coerce(new_world)

    case :ets.lookup(:entities, guid) do
      [{^guid, old_world, old_x, old_y, old_z}] ->
        old_hash = cell(old_world, old_x, old_y, old_z)
        new_hash = cell(new_world, new_x, new_y, new_z)

        :ets.insert(:entities, {guid, new_world, new_x, new_y, new_z})

        if old_hash != new_hash do
          :ets.delete_object(table, {old_hash, guid})
          :ets.insert(table, {new_hash, guid})
        end

      [] ->
        insert(table, guid, new_world, new_x, new_y, new_z)
    end
  end

  def remove(table, guid) do
    case :ets.lookup(:entities, guid) do
      [{^guid, world, x, y, z}] ->
        hash = cell(world, x, y, z)
        :ets.delete_object(table, {hash, guid})
        :ets.delete(:entities, guid)
        :ets.delete(:entity_movement, guid)

      [] ->
        :ets.delete(:entity_movement, guid)
        :ok
    end
  end

  def query_cells(table, world, x, y, z, range) do
    cells_in_range(world, x, y, z, range)
    |> Enum.flat_map(fn cell -> :ets.lookup(table, cell) end)
    |> Enum.map(fn {_hash, guid} -> guid end)
  end

  def query(table, world, x1, y1, z1, range) do
    world = WorldRef.coerce(world)

    cells_in_range(world, x1, y1, z1, range)
    |> Stream.flat_map(fn cell ->
      :ets.lookup(table, cell)
    end)
    |> Stream.map(fn {_hash, guid} ->
      [{^guid, ^world, x2, y2, z2}] = :ets.lookup(:entities, guid)
      distance = distance({x1, y1, z1}, {x2, y2, z2})
      {guid, distance}
    end)
    |> Enum.filter(fn {_guid, distance} ->
      distance <= range
    end)
  end

  @doc """
  Calculates the coordinate boundaries of a spatial hash cell.

  Given a hash tuple `{map, cx, cy}`, it returns a tuple of tuples
  representing the min (inclusive) and max (exclusive) coordinates for the cell.

  The boundaries take into account the rounding behavior of `cell/4`.

  ## Example

      iex> SpatialHash.cell_bounds({ThistleTea.Game.WorldRef.open(0), 1, 2})
      {{124.5, 249.5}, {249.5, 374.5}}

  """
  defdelegate cell_bounds(cell), to: SpatialGrid
  defdelegate cell(world, x, y, z), to: SpatialGrid
  defdelegate cells_in_range(world, x, y, z, range), to: SpatialGrid

  def distance({x1, y1, z1}, {x2, y2, z2}) do
    dx = x2 - x1
    dy = y2 - y1
    dz = z2 - z1
    :math.sqrt(dx * dx + dy * dy + dz * dz)
  end

  def get_entity(guid) do
    case :ets.lookup(:entities, guid) do
      [entity] -> entity
      [] -> nil
    end
  end

  def guids(%WorldRef{} = world) do
    :ets.select(:entities, [{{:"$1", world, :_, :_, :_}, [], [:"$1"]}])
  end

  def entities(table, cell) do
    :ets.lookup(table, cell)
  end

  def cells(table) do
    :ets.match(table, {:"$1", :_})
    |> List.flatten()
    |> MapSet.new()
  end
end
