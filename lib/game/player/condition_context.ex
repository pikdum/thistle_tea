defmodule ThistleTea.Game.Player.ConditionContext do
  @moduledoc """
  Player-owner boundary that collects only the immutable facts requested by a
  collection of loaded condition trees.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Condition.Context
  alias ThistleTea.Game.Entity.Logic.Condition.Requirements
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Exploration
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Exploration, as: ExplorationLoader
  alias ThistleTea.Game.World.Loader.Graveyard
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.System.Party
  alias ThistleTea.Game.World.System.ScriptedEvent

  @content_patch 10

  def build(%Character{} = character, conditions, options \\ []) do
    requirements = Requirements.plan(conditions)
    item_lookup = Keyword.get(options, :item_lookup, &ItemStore.get/1)
    movement_now = Keyword.get(options, :movement_now, Time.now())

    target = subject(character, requirements, item_lookup, movement_now, options)
    source = options |> Keyword.get(:source, target) |> enrich_source(requirements, options)

    Context.new(
      source: source,
      target: target,
      world: world_facts(character, requirements, options),
      now: current_time(requirements, options),
      content_patch: if(MapSet.member?(requirements, :content_patch), do: @content_patch),
      quests: quests(requirements, options),
      environment: environment_facts(character, source, conditions, options)
    )
  end

  def snapshot(%Character{} = character, options \\ []) do
    item_lookup = Keyword.get(options, :item_lookup, &ItemStore.get/1)
    item_ids = character.player |> Inventory.all_owned_items(item_lookup) |> Enum.map(& &1.object.entry) |> Enum.uniq()

    requirements =
      item_ids
      |> Enum.flat_map(
        &[
          {:item_count, :target, &1},
          {:bank_item_count, :target, &1},
          {:item_equipped, :target, &1}
        ]
      )
      |> MapSet.new()
      |> MapSet.put({:active_game_event, 0})
      |> MapSet.put(:content_patch)
      |> MapSet.put(:current_time)

    movement_now = Keyword.get(options, :movement_now, Time.now())
    target = subject(character, requirements, item_lookup, movement_now, options)

    Context.new(
      source: target,
      target: target,
      world: world_facts(character, requirements, options),
      now: current_time(requirements, options),
      content_patch: @content_patch
    )
  end

  def refresh_subject(character, previous \\ nil, options \\ [])

  def refresh_subject(%Character{player: nil}, previous, _options), do: previous

  def refresh_subject(%Character{} = character, previous, options) do
    item_lookup = Keyword.get(options, :item_lookup, &ItemStore.get/1)
    movement_now = Keyword.get(options, :movement_now, Time.now())
    fresh = subject(character, MapSet.new(), item_lookup, movement_now, options)

    case previous do
      %Subject{} = previous ->
        %{
          fresh
          | item_counts: previous.item_counts,
            item_counts_with_bank: previous.item_counts_with_bank,
            equipped_item_ids: previous.equipped_item_ids,
            explored_areas: previous.explored_areas
        }

      _missing ->
        fresh
    end
  end

  defp subject(character, requirements, item_lookup, movement_now, options) do
    player = character.player
    unit = character.unit
    internal = character.internal
    item_ids = requested_ids(requirements, :item_count)
    bank_item_ids = requested_ids(requirements, :bank_item_count)
    equipped_ids = requested_ids(requirements, :item_equipped)
    exploration_ids = requested_exploration_ids(requirements)
    holders = unit.auras || []
    {zone_id, area_id} = zone_and_area(character, requirements, options)

    %Subject{
      guid: character.object.guid,
      kind: :player,
      player_owned?: true,
      entry: character.object.entry,
      position: character.movement_block && character.movement_block.position,
      map_id: internal.world.map_id,
      zone_id: zone_id,
      area_id: area_id,
      level: unit.level,
      gender: unit.gender,
      alive?: Death.alive?(character),
      moving?: Movement.moving?(character, movement_now),
      combat?: internal.in_combat == true,
      health: unit.health,
      max_health: unit.max_health,
      mana: unit.power1,
      max_mana: unit.max_power1,
      aura_ids: aura_ids(holders),
      aura_effects: aura_effects(holders),
      argent_dawn_commission?: argent_dawn_commission?(holders),
      race: unit.race,
      class: unit.class,
      team: Graveyard.team_for_race(unit.race),
      group?: group?(character.object.guid, requirements, options),
      skills: player.skills,
      spellbook: internal.spellbook || %{},
      quest_log: player.quest_log,
      rewarded_quests: player.rewarded_quests,
      reputation: standings(character, requirements, options),
      reputation_ranks: player.reputation.ranks,
      explored_areas: explored_areas(character, exploration_ids, options),
      item_counts: item_counts(player, item_ids, item_lookup),
      item_counts_with_bank: item_counts_with_bank(player, bank_item_ids, item_lookup),
      equipped_item_ids: equipped_item_ids(player, equipped_ids, item_lookup),
      pet_guid: Companion.active_guid(character),
      has_pet?: Companion.active_guid(character) != nil
    }
  end

  defp world_facts(%Character{} = character, requirements, options) do
    %{
      map_id: character.internal.world.map_id,
      active_game_events: active_game_events(requirements, options)
    }
  end

  defp environment_facts(%Character{} = character, %Subject{} = source, conditions, options) do
    environmental = Requirements.environment_conditions(conditions)

    if environmental == [] do
      %{}
    else
      collector = Keyword.get(options, :condition_results, &ScriptedEvent.condition_results/4)

      %{
        condition_results: collector.(character.internal.world, source.guid, character.object.guid, environmental)
      }
    end
  end

  defp enrich_source(%Subject{guid: guid} = source, requirements, options) when is_integer(guid) and guid > 0 do
    metadata = Metadata.get(guid) || %{}
    {position, map_id, zone_id, area_id} = source_location(guid, source, requirements, options)

    %{
      source
      | db_guid: source.db_guid || Map.get(metadata, :db_guid),
        position: source.position || position,
        map_id: source.map_id || map_id,
        zone_id: source.zone_id || zone_id,
        area_id: source.area_id || area_id || Map.get(metadata, :area),
        alive?: fact(source.alive?, metadata, :alive?),
        go_spawned?: fact(source.go_spawned?, metadata, :go_spawned?),
        loot_state: fact(source.loot_state, metadata, :loot_state),
        go_state: fact(source.go_state, metadata, :go_state)
    }
  end

  defp enrich_source(%Subject{} = source, _requirements, _options), do: source

  defp source_location(guid, source, requirements, options) do
    case World.position(guid) do
      {world, x, y, z} ->
        {zone_id, area_id} = source_zone_and_area(source, requirements, options, world.map_id, {x, y, z})
        {{x, y, z}, world.map_id, zone_id, area_id}

      _missing ->
        {nil, nil, nil, nil}
    end
  end

  defp source_zone_and_area(source, requirements, options, map_id, position) do
    if area_required?(requirements) do
      lookup = Keyword.get(options, :zone_and_area, &Pathfinding.get_zone_and_area/2)

      case lookup.(map_id, position) do
        {zone_id, area_id} when is_integer(zone_id) and is_integer(area_id) -> {zone_id, area_id}
        _unknown -> {source.zone_id, source.area_id}
      end
    else
      {source.zone_id, source.area_id}
    end
  end

  defp fact(nil, metadata, key), do: Map.get(metadata, key)
  defp fact(value, _metadata, _key), do: value

  defp active_game_events(requirements, options) do
    if Enum.any?(requirements, &match?({:active_game_event, _id}, &1)) do
      loader = Keyword.get(options, :game_events, fn -> GameEvent.get_events() end)
      MapSet.new(loader.())
    end
  end

  defp current_time(requirements, options) do
    if MapSet.member?(requirements, :current_time) do
      clock = Keyword.get(options, :clock, &local_time/0)
      clock.()
    end
  end

  defp local_time do
    {{year, month, day}, {hour, minute, second}} = :calendar.local_time()
    NaiveDateTime.new!(year, month, day, hour, minute, second)
  end

  defp quests(requirements, options) do
    lookup = Keyword.get(options, :quest_lookup, &QuestLoader.get/1)

    requirements
    |> Enum.flat_map(fn
      {:quest, quest_id} -> [{quest_id, lookup.(quest_id)}]
      _requirement -> []
    end)
    |> Enum.reject(fn {_quest_id, quest} -> is_nil(quest) end)
    |> Map.new()
  end

  defp standings(character, requirements, options) do
    if Enum.any?(requirements, &match?({:quest, _quest_id}, &1)) do
      loader = Keyword.get(options, :reputation_standings, &Reputation.standings/1)
      loader.(character)
    end
  end

  defp group?(guid, requirements, options) do
    if Enum.any?(requirements, &match?({:subject, _target, :group}, &1)) do
      lookup = Keyword.get(options, :group_lookup, &Party.group_of/1)
      lookup.(guid) != nil
    end
  end

  defp requested_ids(requirements, kind) do
    requirements
    |> Enum.flat_map(fn
      {^kind, _target, id} -> [id]
      _requirement -> []
    end)
    |> MapSet.new()
  end

  defp requested_exploration_ids(requirements) do
    requirements
    |> Enum.flat_map(fn
      {:area_explored, _target, area_id} -> [area_id]
      _requirement -> []
    end)
  end

  defp item_counts(player, ids, lookup) do
    Map.new(ids, &{&1, Inventory.count_entry(player, &1, lookup)})
  end

  defp item_counts_with_bank(player, ids, lookup) do
    Map.new(ids, &{&1, Inventory.count_entry_with_bank(player, &1, lookup)})
  end

  defp equipped_item_ids(player, ids, lookup) do
    if MapSet.size(ids) == 0 do
      MapSet.new()
    else
      player
      |> Inventory.equipped_templates(lookup)
      |> Enum.map(& &1.entry)
      |> Enum.filter(&MapSet.member?(ids, &1))
      |> MapSet.new()
    end
  end

  defp explored_areas(_character, [], _options), do: MapSet.new()

  defp explored_areas(character, area_ids, options) do
    area_lookup = Keyword.get(options, :area_lookup, &ExplorationLoader.area/1)

    area_ids
    |> Enum.filter(fn area_id ->
      case area_lookup.(area_id) do
        %{area_bit: area_bit} -> Exploration.explored?(character, area_bit)
        _missing -> false
      end
    end)
    |> MapSet.new()
  end

  defp zone_and_area(%Character{} = character, requirements, options) do
    if area_required?(requirements) do
      lookup = Keyword.get(options, :zone_and_area, &Pathfinding.get_zone_and_area/2)
      {x, y, z, _orientation} = character.movement_block.position

      case lookup.(character.internal.world.map_id, {x, y, z}) do
        {zone_id, area_id} when is_integer(zone_id) and is_integer(area_id) -> {zone_id, area_id}
        _unknown -> {nil, character.internal.area}
      end
    else
      {nil, character.internal.area}
    end
  end

  defp area_required?(requirements) do
    Enum.any?(requirements, &match?({:subject, {:first_available, _source, _target}, :area_id}, &1))
  end

  defp aura_ids(holders) do
    MapSet.new(holders, fn %Holder{spell: %Spell{id: id}} -> id end)
  end

  defp aura_effects(holders) do
    MapSet.new(
      for %Holder{spell: %Spell{id: id}, auras: auras} <- holders,
          %{index: index} <- auras,
          do: {id, index}
    )
  end

  defp argent_dawn_commission?(holders) do
    Enum.any?(holders, fn
      %Holder{spell: %Spell{spell_visual: 3580} = spell} ->
        Spell.attribute?(spell, :ability) or Spell.attribute?(spell, :allow_while_mounted)

      _holder ->
        false
    end)
  end
end
