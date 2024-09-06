defmodule SpatialHash do
  @cell_size 125
  # TODO: benchmark different cell sizes

  def setup_tables do
    :ets.new(:players, [:named_table, :public, :duplicate_bag])
    :ets.new(:mobs, [:named_table, :public, :duplicate_bag])
    :ets.new(:game_objects, [:named_table, :public, :duplicate_bag])
    :ets.new(:locations, [:named_table, :public, :set])
  end

  def insert(table, guid, pid, map, x, y, z) do
    hash = hash_position(map, x, y, z)
    :ets.insert(table, {hash, guid})
    :ets.insert(:locations, {guid, pid, map, x, y, z})
  end

  def update(table, guid, pid, new_map, new_x, new_y, new_z) do
    case :ets.lookup(:locations, guid) do
      [{^guid, _pid, old_map, old_x, old_y, old_z}] ->
        old_hash = hash_position(old_map, old_x, old_y, old_z)
        new_hash = hash_position(new_map, new_x, new_y, new_z)

        # update exact location regardless
        :ets.insert(:locations, {guid, pid, new_map, new_x, new_y, new_z})

        # only update cell if it changed
        if old_hash != new_hash do
          :ets.delete_object(table, {old_hash, guid})
          :ets.insert(table, {new_hash, guid})
        end

      [] ->
        insert(table, guid, pid, new_map, new_x, new_y, new_z)
    end
  end

  def remove(table, guid) do
    case :ets.lookup(:locations, guid) do
      [{^guid, _pid, map, x, y, z}] ->
        hash = hash_position(map, x, y, z)
        :ets.delete_object(table, {hash, guid})
        :ets.delete(:locations, guid)

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
      [{^guid, pid, ^map, x2, y2, z2}] = :ets.lookup(:locations, guid)
      distance = distance({x1, y1, z1}, {x2, y2, z2})
      {guid, pid, distance}
    end)
    |> Enum.filter(fn {_guid, _pid, distance} ->
      distance <= range
    end)
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

  defp distance({x1, y1, z1}, {x2, y2, z2}) do
    dx = x2 - x1
    dy = y2 - y1
    dz = z2 - z1
    :math.sqrt(dx * dx + dy * dy + dz * dz)
  end
end
