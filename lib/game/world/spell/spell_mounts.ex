defmodule ThistleTea.Game.World.Spell.SpellMounts do
  @moduledoc "Resolves mount admission from current world location and cached model capabilities."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Mount
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.Loader.ModelGeometry
  alias ThistleTea.Game.World.Spell.SpellAreas
  alias ThistleTea.Game.World.Spell.SpellEnvironment

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
