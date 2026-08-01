defmodule ThistleTea.Game.SpatialGrid do
  @moduledoc """
  Pure geometry for the world's spatial cells.
  """

  alias ThistleTea.Game.WorldRef

  @cell_size 125

  def max_cell_drift, do: :math.sqrt(2) * @cell_size

  def cell_bounds({_world, cx, cy}) do
    x1 = cx * @cell_size - 0.5
    x2 = (cx + 1) * @cell_size - 0.5
    y1 = cy * @cell_size - 0.5
    y2 = (cy + 1) * @cell_size - 0.5
    {{x1, x2}, {y1, y2}}
  end

  def cell(world, x, y, _z) do
    {WorldRef.coerce(world), Integer.floor_div(round(x), @cell_size), Integer.floor_div(round(y), @cell_size)}
  end

  def cells_in_range(world, x, y, _z, range) do
    world = WorldRef.coerce(world)
    cell_range = div(round(range), @cell_size) + 1
    rounded_x = round(x)
    rounded_y = round(y)

    for dx <- -cell_range..cell_range,
        dy <- -cell_range..cell_range do
      {
        world,
        Integer.floor_div(rounded_x + dx * @cell_size, @cell_size),
        Integer.floor_div(rounded_y + dy * @cell_size, @cell_size)
      }
    end
    |> Enum.uniq()
  end
end
