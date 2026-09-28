defmodule ThistleTea.Game.World.SpellMounts do
  @moduledoc "Resolves mount admission from current world location and cached model capabilities."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Mount
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.Loader.ModelGeometry
  alias ThistleTea.Game.World.SpellAreas
  alias ThistleTea.Game.World.SpellEnvironment

  def context(%Character{} = character, %Spell{} = spell) do
    if Mount.spell?(spell) do
      area = SpellAreas.context(character)

      %Mount.Context{
        area_id: area.area_id,
        mount_allowed?: MapTemplate.mount_allowed?(character.internal.world.map_id),
        outdoors?: SpellEnvironment.outdoors(character),
        display_mountable?: ModelGeometry.get(character.unit.display_id).can_mount?
      }
    end
  end

  def context(_entity, _spell), do: nil
end
