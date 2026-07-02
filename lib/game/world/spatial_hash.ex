defmodule ThistleTea.Game.World.SpatialHash do
  @moduledoc """
  ETS-backed spatial hash with 125-yard cells per entity table, plus active
  spline-movement records, powering range queries and visibility cells.
  """
  @cell_size 125
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

  def put_movement(guid, {_map, _start_position, _spline_nodes, _start_time, _duration} = movement) do
    :ets.insert(:entity_movement, {guid, movement})
  end

  def clear_movement(guid) do
    :ets.delete(:entity_movement, guid)
  end

  def get_movement(guid) do
    case :ets.lookup(:entity_movement, guid) do
      [{^guid, movement}] -> movement
      [] -> nil
    end
  end

  def insert(table, guid, map, x, y, z) do
    hash = cell(map, x, y, z)
    :ets.insert(table, {hash, guid})
    :ets.insert(:entities, {guid, map, x, y, z})
  end

  def update(table, guid, new_map, new_x, new_y, new_z) do
    case :ets.lookup(:entities, guid) do
      [{^guid, old_map, old_x, old_y, old_z}] ->
        old_hash = cell(old_map, old_x, old_y, old_z)
        new_hash = cell(new_map, new_x, new_y, new_z)

        :ets.insert(:entities, {guid, new_map, new_x, new_y, new_z})

        if old_hash != new_hash do
          :ets.delete_object(table, {old_hash, guid})
          :ets.insert(table, {new_hash, guid})
        end

      [] ->
        insert(table, guid, new_map, new_x, new_y, new_z)
    end
  end

  def remove(table, guid) do
    case :ets.lookup(:entities, guid) do
      [{^guid, map, x, y, z}] ->
        hash = cell(map, x, y, z)
        :ets.delete_object(table, {hash, guid})
        :ets.delete(:entities, guid)
        :ets.delete(:entity_movement, guid)

      [] ->
        :ets.delete(:entity_movement, guid)
        :ok
    end
  end

  def query_cells(table, map, x, y, z, range) do
    cells_in_range(map, x, y, z, range)
    |> Enum.flat_map(fn cell -> :ets.lookup(table, cell) end)
    |> Enum.map(fn {_hash, guid} -> guid end)
  end

  def query(table, map, x1, y1, z1, range) do
    cells_in_range(map, x1, y1, z1, range)
    |> Stream.flat_map(fn cell ->
      :ets.lookup(table, cell)
    end)
    |> Stream.map(fn {_hash, guid} ->
      [{^guid, ^map, x2, y2, z2}] = :ets.lookup(:entities, guid)
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

      iex> SpatialHash.cell_bounds({0, 1, 2})
      {{124.5, 249.5}, {249.5, 374.5}}

  """
  def cell_bounds({_map, cx, cy}) do
    x1 = cx * @cell_size - 0.5
    x2 = (cx + 1) * @cell_size - 0.5
    y1 = cy * @cell_size - 0.5
    y2 = (cy + 1) * @cell_size - 0.5
    {{x1, x2}, {y1, y2}}
  end

  def cell(map, x, y, _z) do
    {map, Integer.floor_div(round(x), @cell_size), Integer.floor_div(round(y), @cell_size)}
  end

  def cells_in_range(map, x, y, _z, range) do
    cell_range = div(round(range), @cell_size) + 1
    rounded_x = round(x)
    rounded_y = round(y)

    for dx <- -cell_range..cell_range,
        dy <- -cell_range..cell_range do
      {
        map,
        Integer.floor_div(rounded_x + dx * @cell_size, @cell_size),
        Integer.floor_div(rounded_y + dy * @cell_size, @cell_size)
      }
    end
    |> Enum.uniq()
  end

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

  def entities(table, cell) do
    :ets.lookup(table, cell)
  end

  def cells(table) do
    :ets.match(table, {:"$1", :_})
    |> List.flatten()
    |> MapSet.new()
  end
end
