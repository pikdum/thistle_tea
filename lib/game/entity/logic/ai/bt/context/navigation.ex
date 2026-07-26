defmodule ThistleTea.Game.Entity.Logic.AI.BT.Context.Navigation do
  @moduledoc """
  Path results supplied to behavior-tree navigation by the owning boundary.
  """

  @enforce_keys [:find_path, :find_random_point]
  defstruct [:find_path, :find_random_point]

  def empty do
    %__MODULE__{
      find_path: fn _map_id, _start, _destination -> nil end,
      find_random_point: fn _map_id, _anchor, _radius -> nil end
    }
  end

  def find_path(%__MODULE__{find_path: find_path}, map_id, start, destination) do
    find_path.(map_id, start, destination)
  end

  def find_random_point(%__MODULE__{find_random_point: find_random_point}, map_id, anchor, radius) do
    find_random_point.(map_id, anchor, radius)
  end
end
