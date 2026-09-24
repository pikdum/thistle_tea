defmodule ThistleTea.Game.World.SpellAreas do
  @moduledoc "Builds spell-area snapshots from terrain and the controlling player's cached facts."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Area
  alias ThistleTea.Game.Spell.Area.Context
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Exploration
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding

  def context(caster, spell \\ nil)
  def context(_caster, %Spell{area_rules: []}), do: nil

  def context(caster, _spell) do
    {zone, area} = location(caster)
    %Context{zone_id: zone, area_id: area, player: player(caster)}
  end

  defp player(%Character{} = character), do: Area.player(character)

  defp player(%{object: %{guid: guid}}) do
    with %{owner_guid: owner} when is_integer(owner) and owner > 0 <- Metadata.get(guid),
         %{condition_subject: %Subject{kind: :player} = subject} <- Metadata.get(owner) do
      subject
    else
      _missing -> nil
    end
  end

  defp location(caster) do
    case World.position(caster) do
      {world, x, y, z} ->
        Pathfinding.get_zone_and_area(world.map_id, {x, y, z}) || cached_location(caster, world.map_id)

      _missing ->
        {nil, nil}
    end
  end

  defp cached_location(%{internal: %{area: id}}, map) do
    case Exploration.area(id) do
      %AreaTable{id: area, map: ^map, parent_area_table: 0} -> {area, area}
      %AreaTable{id: area, map: ^map, parent_area_table: zone} -> {zone, area}
      _missing -> {nil, nil}
    end
  end

  defp cached_location(_caster, _map), do: {nil, nil}
end
