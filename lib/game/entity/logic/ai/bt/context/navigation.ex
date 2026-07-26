defmodule ThistleTea.Game.Entity.Logic.AI.BT.Context.Navigation do
  @moduledoc """
  Path results supplied to behavior-tree navigation by the owning boundary.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.Movement

  @enforce_keys [:find_path, :find_random_point]
  defstruct [:find_path, :find_random_point]

  def empty do
    %__MODULE__{
      find_path: fn _map_id, _start, _destination -> nil end,
      find_random_point: fn _map_id, _anchor, _radius -> nil end
    }
  end

  def direct do
    %__MODULE__{
      find_path: fn _map_id, _start, destination -> [destination] end,
      find_random_point: fn _map_id, _anchor, _radius -> nil end
    }
  end

  def find_path(%__MODULE__{find_path: find_path}, map_id, start, destination) do
    find_path.(map_id, start, destination)
  end

  def find_random_point(%__MODULE__{find_random_point: find_random_point}, map_id, anchor, radius) do
    find_random_point.(map_id, anchor, radius)
  end

  def move_to(
        %Context{now: now, navigation: navigation},
        %{internal: %Internal{world: world}, movement_block: %MovementBlock{}} = entity,
        destination,
        opts \\ []
      ) do
    entity = Movement.sync_position(entity, now)
    {start_x, start_y, start_z, _orientation} = entity.movement_block.position

    case find_path(navigation, world.map_id, {start_x, start_y, start_z}, destination) do
      path when is_list(path) ->
        {:ok, Movement.move_along_path(entity, path, opts, now)}

      _no_path ->
        {:error, :no_path, entity}
    end
  end
end
