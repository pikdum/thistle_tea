defmodule ThistleTea.Game.World.Presence do
  @moduledoc """
  Owns publication of a player's metadata and spatial world presence.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Position

  def enter(%Character{} = character, metadata) when is_map(metadata) do
    Metadata.put(character.object.guid, Map.merge(metadata, location_metadata(character)))
    put_position(character)
    :ok
  end

  def relocate(%Character{} = character, metadata \\ %{}) when is_map(metadata) do
    Metadata.update(character.object.guid, Map.merge(metadata, location_metadata(character)))
    put_position(character)
    :ok
  end

  def sync(%Character{} = character, metadata) when is_map(metadata) do
    Metadata.update(character.object.guid, Map.merge(metadata, location_metadata(character)))
  end

  def leave(%Character{} = character) do
    Metadata.delete(character.object.guid)
    Position.remove(character, :players)
    :ok
  end

  defp put_position(%Character{movement_block: %MovementBlock{}} = character) do
    Position.put(character, :players)
  end

  defp location_metadata(
         %Character{
           internal: %Internal{area: area},
           movement_block: %MovementBlock{position: {_x, _y, _z, orientation}}
         } = character
       ) do
    %{area: area, orientation: orientation, viewpoint: viewpoint(character)}
  end

  defp viewpoint(%Character{player: %{farsight: farsight}}) when is_integer(farsight), do: farsight
  defp viewpoint(%Character{}), do: 0
end
