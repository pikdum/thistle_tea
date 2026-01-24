defmodule ThistleTea.Game.World.SpatialHash do
  @cell_size 125
  # TODO: benchmark different cell sizes

  # TODO: benchmark some different options:
  # - :write_concurrency
  # - :read_concurrency
  # - :decentralized_counters
  # - :compressed: doesn't seem worth it, since data is small
  def setup_tables do
    :ets.new(:players, [:named_table, :public, :duplicate_bag])
    :ets.new(:mobs, [:named_table, :public, :duplicate_bag])
    :ets.new(:game_objects, [:named_table, :public, :duplicate_bag])
    :ets.new(:entities, [:named_table, :public, :set])
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

        # update exact location regardless
        :ets.insert(:entities, {guid, new_map, new_x, new_y, new_z})

        # only update cell if it changed
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

  Given a hash tuple `{map, cx, cy, cz}`, it returns a tuple of tuples
  representing the min (inclusive) and max (exclusive) coordinates for the cell.

  The boundaries take into account the rounding behavior of `hash_position/4`.

  ## Example

      iex> SpatialHash.cell_bounds({0, 1, 2, 3})
      {{124.5, 249.5}, {249.5, 374.5}, {374.5, 499.5}}

  """
  def cell_bounds({_map, cx, cy, cz}) do
    x1 = cx * @cell_size - 0.5
    x2 = (cx + 1) * @cell_size - 0.5
    y1 = cy * @cell_size - 0.5
    y2 = (cy + 1) * @cell_size - 0.5
    z1 = cz * @cell_size - 0.5
    z2 = (cz + 1) * @cell_size - 0.5
    {{x1, x2}, {y1, y2}, {z1, z2}}
  end

  defp hash_position(map, x, y, z) do
    {map, div(round(x), @cell_size), div(round(y), @cell_size), div(round(z), @cell_size)}
  end

  defp cells_in_range(map, x, y, z, range) do
    cell_range = div(round(range), @cell_size) + 1
    rounded_x = round(x)
    rounded_y = round(y)
    rounded_z = round(z)

    for dx <- -cell_range..cell_range,
        dy <- -cell_range..cell_range,
        dz <- -cell_range..cell_range do
      {
        map,
        #
        div(rounded_x + dx * @cell_size, @cell_size),
        div(rounded_y + dy * @cell_size, @cell_size),
        div(rounded_z + dz * @cell_size, @cell_size)
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
