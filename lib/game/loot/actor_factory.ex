defmodule ThistleTea.Game.Loot.ActorFactory do
  @moduledoc """
  Builds loot-policy actors from player-owned state or the world read model.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  def for_character(%Character{object: %{guid: guid}} = character, target_guid) do
    %Actor{
      guid: guid,
      group_id: group_id(guid),
      needed_items: Quests.needed_items(character),
      distance: World.distance_between(character, target_guid)
    }
  end

  def for_guid(guid, target_guid) when is_integer(guid) and is_integer(target_guid) do
    %Actor{
      guid: guid,
      group_id: group_id(guid),
      needed_items: needed_items(guid),
      distance: World.distance_between(guid, target_guid)
    }
  end

  defp group_id(guid) do
    case PartySystem.group_of(guid) do
      %Party.Group{id: id} -> id
      _ -> nil
    end
  end

  defp needed_items(guid) do
    case Metadata.query(guid, [:needed_quest_items]) do
      %{needed_quest_items: %MapSet{} = needed_items} -> needed_items
      _ -> :unknown
    end
  end
end
