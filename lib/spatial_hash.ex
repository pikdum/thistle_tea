defmodule SpatialHash do
  @cell_size 50

  def setup_tables do
    :ets.new(:players, [:named_table, :public, :duplicate_bag])
    :ets.new(:mobs, [:named_table, :public, :duplicate_bag])
    :ets.new(:game_objects, [:named_table, :public, :duplicate_bag])
    :ets.new(:locations, [:named_table, :public, :set])
  end

  def insert(table, guid, map, x, y, z) do
    hash = hash_position(map, x, y, z)
    :ets.insert(table, {hash, guid})
    :ets.insert(:locations, {guid, map, x, y, z})
  end

  def update(table, guid, new_map, new_x, new_y, new_z) do
    case :ets.lookup(:locations, guid) do
      [{^guid, old_map, old_x, old_y, old_z}] ->
        old_hash = hash_position(old_map, old_x, old_y, old_z)
        new_hash = hash_position(new_map, new_x, new_y, new_z)

        :ets.delete_object(table, {old_hash, guid})
        :ets.insert(table, {new_hash, guid})
        :ets.insert(:locations, {guid, new_map, new_x, new_y, new_z})

      [] ->
        insert(table, guid, new_map, new_x, new_y, new_z)
    end
  end

  def remove(table, guid) do
    case :ets.lookup(:locations, guid) do
      [{^guid, map, x, y, z}] ->
        hash = hash_position(map, x, y, z)
        :ets.delete_object(table, {hash, guid})
        :ets.delete(:locations, guid)

      [] ->
        :ok
    end
  end

  def query_range(table, map, x, y, z, range) do
    cells_to_check = cells_in_range(map, x, y, z, range)

    nearby_guids =
      cells_to_check
      |> Enum.flat_map(fn cell ->
        :ets.lookup(table, cell)
      end)
      |> Enum.map(fn {_hash, guid} -> guid end)

    nearby_guids
    |> Enum.filter(fn guid ->
      case :ets.lookup(:locations, guid) do
        [{^guid, ^map, obj_x, obj_y, obj_z}] ->
          distance({x, y, z}, {obj_x, obj_y, obj_z}) <= range

        _ ->
          false
      end
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
      {map, div(rounded_x + dx * @cell_size, @cell_size),
       div(rounded_y + dy * @cell_size, @cell_size), div(rounded_z + dz * @cell_size, @cell_size)}
    end
  end

  defp distance({x1, y1, z1}, {x2, y2, z2}) do
    dx = x2 - x1
    dy = y2 - y1
    dz = z2 - z1
    :math.sqrt(dx * dx + dy * dy + dz * dz)
  end
end
