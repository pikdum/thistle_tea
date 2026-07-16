defmodule ThistleTea.Game.Entity.Server.GameObject.Chair do
  @moduledoc """
  Calculates the nearest usable seat on a chair or bench game object.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Chair, as: ChairConfig
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Math

  @max_use_distance 3.0
  @sit_low_chair 4

  def seat(
        %GameObject{
          object: %{scale_x: size},
          internal: %Internal{world: world, chair: %ChairConfig{} = chair},
          movement_block: %MovementBlock{position: {x, y, z, orientation}}
        },
        world,
        {user_x, user_y, user_z}
      )
      when is_number(size) do
    {seat_x, seat_y} = closest_slot({x, y, orientation}, size, chair.slots, {user_x, user_y})
    position = {seat_x, seat_y, z, orientation}

    if Math.distance({user_x, user_y, user_z}, {seat_x, seat_y, z}) <= @max_use_distance do
      {:ok, position, @sit_low_chair + chair.height}
    else
      {:error, :too_far}
    end
  end

  def seat(%GameObject{}, _map, _user_position), do: {:error, :not_a_chair}

  defp closest_slot({x, y, _orientation}, _size, slots, _user_position) when slots <= 0, do: {x, y}

  defp closest_slot({x, y, orientation}, size, slots, {user_x, user_y}) do
    orthogonal_orientation = orientation + :math.pi() / 2

    0..(slots - 1)
    |> Enum.map(fn slot ->
      offset = size * slot - size * (slots - 1) / 2

      {
        x + offset * :math.cos(orthogonal_orientation),
        y + offset * :math.sin(orthogonal_orientation)
      }
    end)
    |> Enum.reduce(nil, fn position, closest ->
      nearer_position(position, closest, {user_x, user_y})
    end)
  end

  defp nearer_position(position, nil, _user_position), do: position

  defp nearer_position({x, y} = position, {closest_x, closest_y} = closest, {user_x, user_y}) do
    distance = distance_2d({user_x, user_y}, {x, y})
    closest_distance = distance_2d({user_x, user_y}, {closest_x, closest_y})

    if distance <= closest_distance, do: position, else: closest
  end

  defp distance_2d({x1, y1}, {x2, y2}) do
    dx = x2 - x1
    dy = y2 - y1
    :math.sqrt(dx * dx + dy * dy)
  end
end
