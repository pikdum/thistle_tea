defmodule ThistleTea.Game.World.Entity.Player.QuestGiver do
  @moduledoc """
  Live world-object resolution and interaction checks for quest exchanges.
  Creature and game-object identities remain separate even when entries match.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.GameObject.GameObjectInteraction
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Movement.Fear
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.Reputation
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Reaction

  def present?(%Character{internal: %{world: world}} = character, guid) do
    Guid.type_id(guid) in [:unit, :game_object] and Entity.online?(guid) and
      match?({^world, _, _, _}, World.position(guid)) and source_allowed?(character, guid)
  end

  def interactable?(%Character{} = character, guid) do
    present?(character, guid) and reactive?(character) and rewardable_life?(character, guid) and
      interactable_source?(character, guid)
  end

  def rewardable?(%Character{} = character, guid) do
    present?(character, guid) and rewardable_life?(character, guid)
  end

  defp reactive?(%Character{internal: internal} = character) do
    is_nil(internal.taxi_flight) and not Fear.active?(character) and
      not Enum.any?([:mod_stun, :mod_confuse, :mod_charm, :mod_possess], &Aura.has_aura?(character, &1))
  end

  defp source_allowed?(character, guid) do
    case Guid.type_id(guid) do
      :unit -> Reputation.can_interact?(character, guid) and not Reaction.hostile?(character, guid)
      :game_object -> match?(%{go_type: 2, go_spawned?: true}, Metadata.get(guid))
    end
  end

  defp rewardable_life?(character, guid) do
    Death.alive?(character) or
      (Guid.type_id(guid) == :unit and match?(%{ghost_visible?: true}, Metadata.get(guid)))
  end

  defp interactable_source?(character, guid) do
    case Guid.type_id(guid) do
      :unit -> creature_interactable?(character, guid)
      :game_object -> object_in_range?(character, guid)
    end
  end

  defp creature_interactable?(character, guid) do
    with %{alive?: true, npc_flags: flags} = metadata <- Metadata.get(guid),
         true <- (flags &&& 0x2) != 0,
         false <- Map.get(metadata, :in_combat, false),
         true <- ((Map.get(metadata, :unit_flags) || 0) &&& 0x03000000) == 0,
         distance when is_number(distance) and distance <= 5.0 <- World.distance_between(character, guid) do
      true
    else
      _invalid -> false
    end
  end

  defp object_in_range?(character, guid) do
    with %GameObjectTemplate{type: 2} = template <- GameObjectTemplateLoader.cached(Guid.entry(guid)),
         %{go_rotation: rotation, go_scale: scale} <- Metadata.get(guid),
         {world, x, y, z} <- World.position(character),
         {^world, ox, oy, oz} <- World.position(guid) do
      GameObjectInteraction.within?({x, y, z}, {ox, oy, oz}, rotation, scale, template.bounds, 5.55556)
    else
      _invalid -> false
    end
  end
end
