defmodule ThistleTea.Game.World.Entity.Player.ObjectTarget do
  @moduledoc """
  Resolves a player's live game-object spell target within interaction range.
  """

  alias ThistleTea.Game.Core.Entity, as: EntityCore
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.Visibility

  def resolve(%{character: %Character{} = character} = state, guid, range)
      when is_integer(guid) and is_number(range) and range > 0 do
    with false <- EntityCore.dead?(character),
         :game_object <- Guid.entity_type(guid),
         true <- Entity.online?(guid) and Visibility.can_see?(state, guid),
         world = character.internal.world,
         {^world, x, y, z} <- World.position(guid),
         distance when is_number(distance) and distance <= range <- World.distance_between(character, guid),
         {cx, cy, cz, _orientation} <- character.movement_block.position,
         true <- Pathfinding.line_of_sight?(world, {cx, cy, cz}, {x, y, z}),
         %GameObjectTemplate{} = template <- GameObjectTemplateLoader.cached(Guid.entry(guid)) do
      {:ok, template}
    else
      distance when is_number(distance) -> {:error, :out_of_range}
      false -> {:error, :bad_targets}
      _ -> {:error, :bad_targets}
    end
  end

  def resolve(_state, _guid, _range), do: {:error, :bad_targets}
end
