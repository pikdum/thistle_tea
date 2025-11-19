defmodule ThistleTea.Game.Math do
  @moduledoc """
  Collection of math related utility functions.
  """

  @range 250

  def random_int(min, max) when is_float(min) and is_float(max) do
    random_int(round(min), round(max))
  end

  def random_int(min, max) when is_integer(min) and is_integer(max) do
    :rand.uniform(max - min + 1) + min - 1
  end

  def within_range(a, b) do
    within_range(a, b, @range)
  end

  def within_range(a, b, range) do
    {x1, y1, z1} = a
    {x2, y2, z2} = b

    abs(x1 - x2) <= range && abs(y1 - y2) <= range && abs(z1 - z2) <= range
  end

  def movement_duration({x0, y0, z0}, {x1, y1, z1}, speed) when is_float(speed) and speed > 0 do
    distance = :math.sqrt(:math.pow(x1 - x0, 2) + :math.pow(y1 - y0, 2) + :math.pow(z1 - z0, 2))
    distance / speed
  end

  def movement_duration(path_list, speed) when is_list(path_list) do
    path_list
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [start, finish] -> movement_duration(start, finish, speed) end)
    |> Enum.sum()
  end
end
