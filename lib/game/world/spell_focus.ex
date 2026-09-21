defmodule ThistleTea.Game.World.SpellFocus do
  @moduledoc """
  Finds spawned spell-focus objects using cached templates and live world presence.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Focus
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader
  alias ThistleTea.Game.World.Metadata

  def find(%Character{} = entity, %Spell{required_focus_id: id}) when is_integer(id) and id > 0 do
    caster_radius = caster_radius(entity)
    search_range = Focus.range(TemplateLoader.focus_radius(id), caster_radius)

    entity
    |> World.nearby_game_objects(search_range)
    |> Enum.sort_by(fn {guid, distance} -> {distance, guid} end)
    |> Enum.find_value(fn {guid, distance} ->
      template = TemplateLoader.cached(Guid.entry(guid))

      with {^id, radius} <- Focus.definition(template),
           true <- distance < Focus.range(radius, caster_radius),
           %{go_spawned?: true} <- Metadata.get(guid),
           {_world, _x, _y, _z} = position <- World.position(guid) do
        %Focus{guid: guid, id: id, position: position}
      else
        _unavailable -> nil
      end
    end)
  end

  def find(_entity, _spell), do: nil

  defp caster_radius(%{unit: %{bounding_radius: radius}}), do: radius
  defp caster_radius(_entity), do: nil
end
