defmodule ThistleTea.Game.World.Presence do
  @moduledoc """
  Owns publication of a player's metadata and spatial world presence.
  """

  alias ThistleTea.Game.Core.Aura.Invulnerability
  alias ThistleTea.Game.Core.Combat.FeignDeath
  alias ThistleTea.Game.Core.Combat.PlayerCombat
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Appearance
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Item.ItemEligibility
  alias ThistleTea.Game.Core.OutdoorPvp.Participation
  alias ThistleTea.Game.Core.Pet.PlayerPossession
  alias ThistleTea.Game.Core.Pvp
  alias ThistleTea.Game.Core.Realm
  alias ThistleTea.Game.World.Loader.Faction, as: FactionLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.Social.Notifier, as: SocialNotifier
  alias ThistleTea.Game.World.System.Party

  def enter(%Character{} = character, metadata) when is_map(metadata) do
    Metadata.put(character.object.guid, Map.merge(metadata, state_metadata(character)))
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
    Metadata.update(character.object.guid, Map.merge(metadata, state_metadata(character)))
  end

  def leave(%Character{} = character) do
    published? = Metadata.get(character.object.guid) != nil
    Metadata.delete(character.object.guid)
    Position.remove(character, :players)
    if published?, do: SocialNotifier.offline(character.object.guid)
    :ok
  end

  defp state_metadata(character) do
    character
    |> location_metadata()
    |> Map.put(:item_eligibility, ItemEligibility.from_character(character))
    |> Map.put(:invulnerability_interruptible?, Invulnerability.carrier?(character))
    |> Map.merge(PlayerCombat.projection(character))
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
      health_deficit: Entity.health_deficit(character),
      feigning_death?: FeignDeath.successful?(character),
      shapeshift_form: shapeshift_form(character),
      area: area,
      chat_status: character.internal.chat_status,
      orientation: orientation,
      transport_guid: character.movement_block.transport_guid,
      lateral_speed: MovementBlock.lateral_speed(character.movement_block),
      viewpoint: viewpoint(character),
      creature_type: Character.creature_type(character),
      honor_rank: honor_rank(character),
      pvp?: Pvp.active?(character),
      pvp_combat?: Pvp.combat?(character),
      free_for_all?: Pvp.free_for_all?(character),
      contested_pvp?: Pvp.contested?(character),
      outdoor_pvp_eligible?: Participation.eligible?(character, Realm.pvp_rules()),
      group_id: group_id(character.object.guid)
    }
    |> Map.put(:owner_guid, PlayerPossession.controller(character))
    |> Map.merge(Appearance.metadata(character))
    |> Map.merge(faction_metadata(character))
  end

  defp faction_metadata(%Character{unit: %Unit{faction_template: faction}}), do: FactionLoader.metadata(faction)
  defp faction_metadata(%Character{}), do: %{}

  defp honor_rank(%Character{player: %{honor_rank: rank}}), do: rank || 0
  defp honor_rank(%Character{}), do: 0

  defp shapeshift_form(%Character{unit: %Unit{shapeshift_form: form}}), do: form || 0
  defp shapeshift_form(%Character{}), do: 0

  defp group_id(guid) do
    case Party.group_of(guid) do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp viewpoint(%Character{player: %{farsight: farsight}}) when is_integer(farsight), do: farsight
  defp viewpoint(%Character{}), do: 0
end
