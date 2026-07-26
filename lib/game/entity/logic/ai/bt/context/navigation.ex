defmodule ThistleTea.Game.Entity.Logic.AI.BT.Context.Navigation do
  @moduledoc """
  Immutable navigation observations supplied for one behavior-tree tick.
  """

  @enforce_keys [:random_points]
  defstruct [:random_points]

  def empty, do: %__MODULE__{random_points: %{}}
  def direct, do: empty()

  def new(points) when is_map(points), do: %__MODULE__{random_points: points}

  def find_random_point(%__MODULE__{random_points: points}, map_id, anchor, radius) do
    Map.get(points, {map_id, anchor, radius})
  end
end
