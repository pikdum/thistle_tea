defmodule ThistleTea.Game.Loot.ActorFactory do
  @moduledoc """
  Builds loot-policy actors from player-owned state or the world read model.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Condition.Context
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Player.ConditionContext
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Graveyard
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  def for_character(%Character{object: %{guid: guid}} = character, target_guid) do
    condition_context = character_condition_context(character, target_guid)

    %Actor{
      guid: guid,
      group_id: group_id(guid),
      needed_items: Quests.needed_items(character),
      distance: World.distance_between(character, target_guid),
      condition_context: condition_context
    }
  end

  def for_guid(guid, target_guid) when is_integer(guid) and is_integer(target_guid) do
    %Actor{
      guid: guid,
      group_id: group_id(guid),
      needed_items: needed_items(guid),
      distance: World.distance_between(guid, target_guid),
      condition_context: remote_condition_context(guid, target_guid)
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

  defp with_source(%Context{} = context, target_guid) do
    %{context | source: loot_subject(target_guid)}
  end

  defp character_condition_context(
         %Character{unit: %Unit{}, player: %Player{}, internal: %Internal{world: world}} = character,
         target_guid
       )
       when not is_nil(world) do
    character |> ConditionContext.snapshot() |> with_source(target_guid)
  end

  defp character_condition_context(%Character{}, _target_guid), do: nil

  defp remote_condition_context(guid, target_guid) do
    metadata = Metadata.get(guid) || %{}
    target = remote_subject(guid, metadata)

    Context.new(
      source: loot_subject(target_guid),
      target: target,
      world: %{active_game_events: MapSet.new(GameEvent.get_events())},
      content_patch: 10
    )
  end

  defp remote_subject(guid, metadata) do
    base =
      case Map.get(metadata, :condition_subject) do
        %Subject{} = subject -> subject
        _missing -> %Subject{}
      end

    race = Map.get(metadata, :race, base.race)
    health = Map.get(metadata, :health_pct, base.health)
    mana = Map.get(metadata, :mana_pct, base.mana)
    aura_ids = projected_aura_ids(metadata, base.aura_ids)

    %{
      base
      | guid: guid,
        kind: :player,
        player_owned?: true,
        race: race,
        class: Map.get(metadata, :class, base.class),
        gender: Map.get(metadata, :gender, base.gender),
        level: Map.get(metadata, :level, base.level),
        team: if(is_integer(race), do: Graveyard.team_for_race(race)),
        area_id: Map.get(metadata, :area, base.area_id),
        alive?: Map.get(metadata, :alive?, base.alive?),
        moving?: Map.get(metadata, :moving?, base.moving?),
        combat?: Map.get(metadata, :in_combat, base.combat?),
        health: health,
        max_health: if(is_number(health), do: 100),
        mana: mana,
        max_mana: if(is_number(mana), do: 100),
        aura_ids: aura_ids,
        group?: group_id(guid) != nil
    }
  end

  defp projected_aura_ids(metadata, fallback) do
    case Map.fetch(metadata, :aura_stacks) do
      {:ok, aura_stacks} when is_map(aura_stacks) -> aura_stacks |> Map.keys() |> MapSet.new()
      _missing -> fallback
    end
  end

  defp loot_subject(guid) do
    {position, map_id, zone_id, area_id} = loot_location(guid)

    %Subject{
      guid: guid,
      kind: Guid.entity_type(guid),
      entry: Guid.entry(guid),
      db_guid: loot_db_guid(guid),
      position: position,
      map_id: map_id,
      zone_id: zone_id,
      area_id: area_id
    }
  end

  defp loot_location(guid) do
    case World.position(guid) do
      {world, x, y, z} = position ->
        case Pathfinding.get_zone_and_area(world.map_id, {x, y, z}) do
          {zone_id, area_id} -> {position, world.map_id, zone_id, area_id}
          _unknown -> {position, world.map_id, nil, nil}
        end

      _missing ->
        {nil, nil, nil, nil}
    end
  end

  defp loot_db_guid(guid) do
    case Metadata.query(guid, [:db_guid]) do
      %{db_guid: db_guid} when is_integer(db_guid) and db_guid > 0 -> db_guid
      _missing_or_summoned -> nil
    end
  end
end
