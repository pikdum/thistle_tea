defmodule ThistleTea.Game.World.Entity.Player.NpcReach do
  @moduledoc """
  Whether a player stands close enough to use a creature's services.

  vmangos measures its five-yard INTERACTION_DISTANCE past both bodies'
  bounding radii. The client, too, lets a player use a large creature from
  beyond five yards of its center, so measuring between centers silently
  ignored vendors, trainers, and quest givers the player could click.
  """

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  @interaction_distance 5.0

  def within?(%Character{unit: unit} = character, guid) when is_integer(guid) do
    case World.distance_between(character, guid) do
      distance when is_number(distance) ->
        distance <= @interaction_distance + radius(unit.bounding_radius) + creature_radius(guid)

      _elsewhere ->
        false
    end
  end

  def within?(_character, _guid), do: false

  defp creature_radius(guid) do
    case Metadata.query(guid, [:bounding_radius]) do
      %{bounding_radius: radius} -> radius(radius)
      _unknown -> 0.0
    end
  end

  defp radius(radius) when is_number(radius) and radius > 0, do: radius
  defp radius(_radius), do: 0.0
end
