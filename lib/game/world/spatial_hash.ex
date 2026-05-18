defmodule ThistleTea.Game.World.SpatialHash do
  @cell_size 125
  @cell_table_options [:named_table, :public, :duplicate_bag, read_concurrency: true, write_concurrency: :auto]
  @entity_table_options [:named_table, :public, :set, read_concurrency: true, write_concurrency: :auto]

  def setup_tables do
    :ets.new(:players, @cell_table_options)
    :ets.new(:mobs, @cell_table_options)
    :ets.new(:game_objects, @cell_table_options)
    :ets.new(:entities, @entity_table_options)
  end

  def insert(table, guid, map, x, y, z) do
    hash = hash_position(map, x, y, z)
    :ets.insert(table, {hash, guid})
    :ets.insert(:entities, {guid, map, x, y, z})
  end

  def update(table, guid, new_map, new_x, new_y, new_z) do
    case :ets.lookup(:entities, guid) do
      [{^guid, old_map, old_x, old_y, old_z}] ->
        old_hash = hash_position(old_map, old_x, old_y, old_z)
        new_hash = hash_position(new_map, new_x, new_y, new_z)

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
        hash = hash_position(map, x, y, z)
        :ets.delete_object(table, {hash, guid})
        :ets.delete(:entities, guid)

      [] ->
        :ok
    end
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

  The boundaries take into account the rounding behavior of `hash_position/4`.

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

  defp hash_position(map, x, y, _z) do
    {map, div(round(x), @cell_size), div(round(y), @cell_size)}
  end

  defp cells_in_range(map, x, y, _z, range) do
    cell_range = div(round(range), @cell_size) + 1
    rounded_x = round(x)
    rounded_y = round(y)

    for dx <- -cell_range..cell_range,
        dy <- -cell_range..cell_range do
      {
        map,
        div(rounded_x + dx * @cell_size, @cell_size),
        div(rounded_y + dy * @cell_size, @cell_size)
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
