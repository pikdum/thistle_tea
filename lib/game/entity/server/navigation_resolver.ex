defmodule ThistleTea.Game.Entity.Server.NavigationResolver do
  @moduledoc """
  Resolves navigation intents at the entity-owner boundary.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.World.Pathfinding

  def resolve(entity, now, find_path \\ &Pathfinding.find_path/3)

  def resolve(%{internal: %Internal{}, movement_block: %MovementBlock{}} = entity, now, find_path)
      when is_integer(now) and is_function(find_path, 3) do
    {entity, intents} = NavigationIntent.drain(entity)
    Enum.reduce(intents, entity, &resolve_intent(&2, &1, now, find_path))
  end

  def resolve(entity, _now, _find_path), do: entity

  defp resolve_intent(
         %{internal: %Internal{world: world}} = entity,
         %NavigationIntent{destination: destination, opts: opts},
         now,
         find_path
       ) do
    entity = Movement.sync_position(entity, now)
    {start_x, start_y, start_z, _orientation} = entity.movement_block.position

    case find_path.(world.map_id, {start_x, start_y, start_z}, destination) do
      path when is_list(path) -> Movement.move_along_path(entity, path, opts, now)
      _no_path -> entity
    end
  end
end
