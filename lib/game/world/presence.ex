defmodule ThistleTea.Game.World.Presence do
  @moduledoc """
  Owns publication of a player's metadata and spatial world presence.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.FeignDeath
  alias ThistleTea.Game.Entity.Logic.PlayerPossession
  alias ThistleTea.Game.Entity.Logic.Pvp
  alias ThistleTea.Game.Social.Notifier, as: SocialNotifier
  alias ThistleTea.Game.World.Loader.Faction, as: FactionLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.System.Party

  def enter(%Character{} = character, metadata) when is_map(metadata) do
    Metadata.put(character.object.guid, Map.merge(metadata, location_metadata(character)))
    put_position(character)
    SocialNotifier.online(character.object.guid)
    :ok
  end

  def relocate(%Character{} = character, metadata \\ %{}) when is_map(metadata) do
    Metadata.update(character.object.guid, Map.merge(metadata, location_metadata(character)))
    put_position(character)
    :ok
  end

  def relocate_client(%Character{} = character, metadata, velocity, now, projection_duration_ms)
      when is_map(metadata) do
    Metadata.update(character.object.guid, Map.merge(metadata, location_metadata(character)))
    projection = Position.client_motion(character, velocity, now, projection_duration_ms)
    Position.put(character, :players, projection)
    :ok
  end

  def sync(%Character{} = character, metadata) when is_map(metadata) do
    Metadata.update(character.object.guid, Map.merge(metadata, location_metadata(character)))
  end

  def leave(%Character{} = character) do
    published? = Metadata.get(character.object.guid) != nil
    Metadata.delete(character.object.guid)
    Position.remove(character, :players)
    if published?, do: SocialNotifier.offline(character.object.guid)
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
    %{
      health_deficit: Core.health_deficit(character),
      feigning_death?: FeignDeath.successful?(character),
      area: area,
      chat_status: character.internal.chat_status,
      orientation: orientation,
      viewpoint: viewpoint(character),
      creature_type: Character.creature_type(character),
      honor_rank: honor_rank(character),
      pvp?: Pvp.active?(character),
      pvp_combat?: Pvp.combat?(character),
      free_for_all?: Pvp.free_for_all?(character),
      contested_pvp?: Pvp.contested?(character),
      group_id: group_id(character.object.guid)
    }
    |> Map.put(:owner_guid, PlayerPossession.controller(character))
    |> Map.merge(faction_metadata(character))
  end

  defp faction_metadata(%Character{unit: %Unit{faction_template: faction}}), do: FactionLoader.metadata(faction)
  defp faction_metadata(%Character{}), do: %{}

  defp honor_rank(%Character{player: %{honor_rank: rank}}), do: rank || 0
  defp honor_rank(%Character{}), do: 0

  defp group_id(guid) do
    case Party.group_of(guid) do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp viewpoint(%Character{player: %{farsight: farsight}}) when is_integer(farsight), do: farsight
  defp viewpoint(%Character{}), do: 0
end
