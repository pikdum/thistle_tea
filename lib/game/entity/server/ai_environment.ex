defmodule ThistleTea.Game.Entity.Server.AIEnvironment do
  @moduledoc """
  Builds the world, navigation, time, and randomness environment consumed by
  one entity behavior-tree tick.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Data.Component.Internal.Waypoint
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.Possession
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Navigation, as: NavigationMemory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Confusion
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Request
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Distancing
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells, as: MobSpells
  alias ThistleTea.Game.Entity.Logic.AI.EventAI
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Condition.Requirements
  alias ThistleTea.Game.Entity.Logic.CreatureMovement
  alias ThistleTea.Game.Entity.Logic.Fear
  alias ThistleTea.Game.Entity.Server.FormationEnvironment
  alias ThistleTea.Game.Entity.Server.NavigationResolver
  alias ThistleTea.Game.Entity.SpellReception
  alias ThistleTea.Game.Player.Movement, as: PlayerMovement
  alias ThistleTea.Game.Spell.Area
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CombatLeashes
  alias ThistleTea.Game.World.InstanceData
  alias ThistleTea.Game.World.Loader.CreatureArchetype, as: CreatureArchetypeLoader
  alias ThistleTea.Game.World.Loader.Waypoint, as: WaypointLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.Pathfinding.Aquatic
  alias ThistleTea.Game.World.SpellAreas
  alias ThistleTea.Game.World.System.ScriptedEvent

  @pet_observation_radius 20.0
  @totem_observation_radius 30.0

  def context(entity, now \\ Time.now(), request \\ %Request{}, options \\ [])

  def context(
        entity,
        now,
        %Request{actors: actors, radius: requested_radius, game_object_radius: requested_game_object_radius} = request,
        options
      )
      when is_integer(now) and is_list(actors) and is_number(requested_radius) and requested_radius >= 0 and
             is_number(requested_game_object_radius) and requested_game_object_radius >= 0 and is_list(options) do
    conditions = all_conditions(entity, request)
    requirements = Requirements.plan(conditions)
    script_targets = script_target_results(entity, request.script_targets)
    observed_actors = actors ++ Map.values(script_targets)
    perception = perception(entity, now, observed_actors, requested_radius, requested_game_object_radius)
    groups = condition_groups(entity, request, perception, conditions)
    condition_results = script_condition_results(entity, groups)
    condition_target = explicit_actor(actors) || event_ai_target(entity)
    random = random()

    %Context{
      now: now,
      perception: perception,
      random: random,
      navigation: navigation(entity, now, perception, random),
      waypoints: WaypointLoader.context(),
      script_conditions: Map.get(condition_results, condition_target, %{}),
      script_conditions_by_target: condition_results,
      script_targets: script_targets,
      condition_now: local_time(),
      condition_area: condition_area(entity, requirements),
      spell_area: spell_area(entity),
      liquid_surface: liquid_surface(entity),
      body_height: PlayerMovement.body_height(entity),
      instance_data: instance_data(entity, requirements, options),
      formation: FormationEnvironment.snapshot(entity, now),
      shared_leash_time: CombatLeashes.last_extended_at(entity),
      aura_contexts: SpellReception.aura_contexts(entity, now),
      creature_archetypes: creature_archetypes(entity, request.creature_entries)
    }
  end

  defp liquid_surface(%Character{} = character), do: PlayerMovement.liquid_surface(character)
  defp liquid_surface(_entity), do: nil

  defp spell_area(%{internal: %{spellbook: spellbook}} = entity) when is_map(spellbook) do
    if Enum.any?(Map.values(spellbook), &Area.restricted?/1), do: SpellAreas.context(entity)
  end

  defp spell_area(_entity), do: nil

  def move_to(entity, destination, opts \\ [], now \\ Time.now()) do
    {stop_patrol?, opts} = Keyword.pop(opts, :stop_patrol?, false)

    entity
    |> prepare_point_movement(stop_patrol?)
    |> NavigationIntent.enqueue(destination, opts)
    |> NavigationResolver.resolve(now)
  end

  defp prepare_point_movement(
         %Mob{internal: %Internal{blackboard: %Blackboard{} = blackboard} = internal} = entity,
         true
       ) do
    %{entity | internal: %{internal | blackboard: Blackboard.idle_movement(blackboard)}}
  end

  defp prepare_point_movement(entity, _stop_patrol?), do: entity

  defp perception(entity, now, observed_guids, requested_radius, requested_game_object_radius) do
    radius = max(observation_radius(entity), requested_radius)
    game_object_radius = max(game_object_observation_radius(entity), requested_game_object_radius)
    nearby = nearby_guids(entity, radius, game_object_radius)

    guids =
      [own_guid(entity), Fear.source_guid(entity), Distancing.target_guid(entity) | direct_guids(entity)]
      |> Enum.concat(observed_guids)
      |> Enum.concat(Enum.flat_map(nearby, fn {_kind, entries} -> Enum.map(entries, &elem(&1, 0)) end))
      |> Enum.filter(&(is_integer(&1) and &1 > 0))
      |> Enum.uniq()

    line_of_sight_guids = line_of_sight_guids(entity, now, observed_guids, nearby)
    observations = Map.new(guids, &{&1, observe(entity, &1, now, line_of_sight_guids)})
    nearby = Map.new(nearby, fn {kind, entries} -> {kind, observed_distances(entries, observations)} end)

    Perception.new(now, origin(entity), observations, nearby)
  end

  defp observation_radius(%Character{}), do: 0.0

  defp observation_radius(%Mob{} = entity) do
    [
      base_observation_radius(entity),
      MobSpells.observation_radius(entity),
      EventAI.observation_radius(entity),
      waypoint_observation_radius(entity)
    ]
    |> Enum.max()
  end

  defp observation_radius(_entity), do: 0.0

  defp game_object_observation_radius(%Mob{} = entity) do
    max(
      EventAI.game_object_observation_radius(entity),
      waypoint_game_object_observation_radius(entity)
    )
  end

  defp game_object_observation_radius(_entity), do: 0.0

  defp base_observation_radius(%Mob{internal: %Internal{pet: %Pet{}}}), do: @pet_observation_radius
  defp base_observation_radius(%Mob{internal: %Internal{totem: %Totem{}}}), do: @totem_observation_radius
  defp base_observation_radius(%Mob{internal: %Internal{in_combat: true}}), do: MobBT.combat_observation_radius()
  defp base_observation_radius(%Mob{}), do: MobBT.max_aggro_radius()

  defp waypoint_observation_radius(%Mob{} = entity) do
    entity
    |> waypoint_route()
    |> waypoint_route_observation_radius()
  end

  defp waypoint_route(%Mob{
         internal: %Internal{
           blackboard: %Blackboard{navigation: %NavigationMemory{scripted_waypoint_route: %WaypointRoute{} = route}}
         }
       }), do: route

  defp waypoint_route(%Mob{internal: %Internal{spawn: %Spawn{waypoint_route: %WaypointRoute{} = route}}}), do: route
  defp waypoint_route(%Mob{}), do: nil

  defp waypoint_route_observation_radius(%WaypointRoute{points: points}) when is_map(points) do
    points
    |> Map.values()
    |> Enum.flat_map(fn
      %Waypoint{script_steps: steps} when is_list(steps) -> steps
      _waypoint -> []
    end)
    |> Script.observation_radius()
  end

  defp waypoint_route_observation_radius(nil), do: 0.0

  defp waypoint_game_object_observation_radius(%Mob{} = entity) do
    entity
    |> waypoint_route()
    |> waypoint_route_game_object_observation_radius()
  end

  defp waypoint_route_game_object_observation_radius(%WaypointRoute{points: points}) when is_map(points) do
    points
    |> Map.values()
    |> Enum.flat_map(fn
      %Waypoint{script_steps: steps} when is_list(steps) -> steps
      _waypoint -> []
    end)
    |> Script.game_object_observation_radius()
  end

  defp waypoint_route_game_object_observation_radius(nil), do: 0.0

  defp nearby_guids(entity, radius, game_object_radius) do
    nearby =
      if radius > 0 do
        %{
          mobs: World.nearby_mobs(entity, radius),
          players: World.nearby_players(entity, radius)
        }
      else
        %{mobs: [], players: []}
      end

    if game_object_radius > 0 do
      Map.put(nearby, :game_objects, World.nearby_game_objects(entity, game_object_radius))
    else
      Map.put(nearby, :game_objects, [])
    end
  end

  defp direct_guids(%Character{internal: %{possession: %Possession{} = control}, unit: %{target: target}}) do
    controller = Metadata.get(control.caster_guid) || %{}
    [control.caster_guid, control.command_target, target, controller[:victim_guid] | controller[:combat_targets] || []]
  end

  defp direct_guids(%{
         internal: %Internal{pet: %Pet{owner_guid: owner_guid}, threat: threat},
         unit: %Unit{target: target}
       }) do
    [owner_guid, target | threat_guids(threat)]
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
  end

  defp direct_guids(%{internal: %Internal{totem: %Totem{owner_guid: owner_guid}}, unit: %Unit{target: target}}) do
    Enum.filter([owner_guid, target], &(is_integer(&1) and &1 > 0))
  end

  defp direct_guids(%{internal: %Internal{auto_shot: auto_shot, threat: threat}, unit: %Unit{target: target}}) do
    [auto_repeat_target(auto_shot), target | threat_guids(threat)]
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
  end

  defp direct_guids(_entity), do: []

  defp script_condition_results(%{object: %{guid: source_guid}, internal: %Internal{world: world}}, groups)
       when is_map(groups) do
    ScriptedEvent.condition_results_by_target(world, source_guid, groups)
  end

  defp script_condition_results(_entity, _groups), do: %{}

  defp condition_groups(entity, request, perception, conditions) do
    actor = explicit_actor(request.actors)

    %{}
    |> put_condition_group(actor, request.script_conditions)
    |> put_condition_group(actor || event_ai_target(entity), event_ai_conditions(entity))
    |> put_condition_group(nil, waypoint_conditions(entity))
    |> put_selected_condition_groups(perception, conditions)
  end

  defp put_selected_condition_groups(groups, perception, conditions) do
    case Requirements.environment_conditions(conditions) do
      [] ->
        groups

      environmental ->
        Enum.reduce(Map.keys(perception.entities), groups, fn guid, groups ->
          Map.update(groups, guid, environmental, &Enum.uniq(&1 ++ environmental))
        end)
    end
  end

  defp put_condition_group(groups, target_guid, conditions) do
    environmental = Requirements.environment_conditions(conditions)

    if environmental == [] do
      groups
    else
      Map.update(groups, target_guid, environmental, &Enum.uniq(&1 ++ environmental))
    end
  end

  defp explicit_actor(actors), do: Enum.find(actors, &(is_integer(&1) and &1 > 0))

  defp event_ai_target(%Mob{unit: %Unit{target: target}}) when is_integer(target) and target > 0, do: target
  defp event_ai_target(_entity), do: nil

  defp all_conditions(entity, request) do
    (request.script_conditions ++ event_ai_conditions(entity) ++ waypoint_conditions(entity))
    |> Enum.uniq()
  end

  defp creature_archetypes(entity, requested) do
    event_steps = entity |> EventAI.events() |> Enum.flat_map(&List.flatten(&1.actions))
    route_steps = waypoint_steps(entity)
    entries = requested ++ Script.creature_entries(event_steps ++ route_steps)
    CreatureArchetypeLoader.get_many(entries)
  end

  defp waypoint_steps(%Mob{} = entity) do
    case waypoint_route(entity) do
      %WaypointRoute{points: points} when is_map(points) ->
        points |> Map.values() |> Enum.flat_map(& &1.script_steps)

      _ ->
        []
    end
  end

  defp waypoint_steps(_entity), do: []

  defp event_ai_conditions(%Mob{} = entity), do: EventAI.conditions(entity)
  defp event_ai_conditions(_entity), do: []

  defp waypoint_conditions(%Mob{} = entity) do
    case waypoint_route(entity) do
      %WaypointRoute{points: points} when is_map(points) ->
        points
        |> Map.values()
        |> Enum.flat_map(fn
          %Waypoint{script_steps: steps} when is_list(steps) -> steps
          _waypoint -> []
        end)
        |> Script.conditions()

      nil ->
        []
    end
  end

  defp waypoint_conditions(_entity), do: []

  defp script_target_results(%{internal: %Internal{world: world}} = entity, requested) when is_list(requested) do
    selectors = Enum.uniq(requested ++ entity_script_target_requests(entity))
    ScriptedEvent.target_results(world, selectors)
  end

  defp script_target_results(_entity, _requested), do: %{}

  defp entity_script_target_requests(%Mob{} = entity) do
    EventAI.script_target_requests(entity) ++ waypoint_script_target_requests(entity)
  end

  defp entity_script_target_requests(_entity), do: []

  defp waypoint_script_target_requests(%Mob{} = entity) do
    case waypoint_route(entity) do
      %WaypointRoute{points: points} when is_map(points) ->
        points
        |> Map.values()
        |> Enum.flat_map(fn
          %Waypoint{script_steps: steps} when is_list(steps) -> steps
          _waypoint -> []
        end)
        |> Script.target_requests()

      nil ->
        []
    end
  end

  defp auto_repeat_target(%{target_guid: target_guid}), do: target_guid
  defp auto_repeat_target(_auto_repeat), do: nil

  defp own_guid(%{object: %{guid: guid}}) when is_integer(guid) and guid > 0, do: guid
  defp own_guid(_entity), do: nil

  defp threat_guids(threat) when is_map(threat), do: Map.keys(threat)
  defp threat_guids(_threat), do: []

  defp local_time do
    {{year, month, day}, {hour, minute, second}} = :calendar.local_time()
    NaiveDateTime.new!(year, month, day, hour, minute, second)
  end

  defp condition_area(entity, requirements) do
    if Enum.any?(requirements, &match?({:subject, {:first_available, _source, _target}, :area_id}, &1)) do
      case origin(entity) do
        {world, x, y, z} -> Pathfinding.get_zone_and_area(world.map_id, {x, y, z})
        _missing -> nil
      end
    end
  end

  defp instance_data(%{internal: %Internal{world: world}}, requirements, options) do
    fields =
      requirements
      |> Enum.flat_map(fn
        {:instance_data, field} -> [field]
        _requirement -> []
      end)
      |> Enum.uniq()

    if fields != [] do
      lookup = Keyword.get(options, :instance_data, &InstanceData.read/2)
      lookup.(world, fields)
    end
  end

  defp instance_data(_entity, _requirements, _options), do: nil

  defp observe(entity, guid, now, line_of_sight_guids) do
    position = World.position(guid, now)

    %Observation{
      guid: guid,
      position: position,
      grounded_position: World.grounded_target_position(guid, now),
      distance: distance(origin(entity), position),
      metadata: Metadata.get(guid),
      swimmable?: swimmable_target?(entity, position),
      moving?: World.moving?(guid, now),
      line_of_sight?: line_of_sight?(entity, guid, line_of_sight_guids)
    }
  end

  defp swimmable_target?(%Mob{} = entity, {%{map_id: map_id}, x, y, z}) do
    case NavigationResolver.path_options(entity) do
      [] -> nil
      opts -> Aquatic.water(map_id, {x, y, z}, opts[:minimum_depth]) != nil
    end
  end

  defp swimmable_target?(_entity, _position), do: nil

  defp line_of_sight?(entity, guid, line_of_sight_guids) do
    guid == own_guid(entity) or
      not MapSet.member?(line_of_sight_guids, guid) or
      World.line_of_sight?(entity, guid)
  end

  defp line_of_sight_guids(entity, now, observed_guids, nearby) do
    observed_guids
    |> Enum.concat(direct_guids(entity))
    |> Enum.concat(nearby_line_of_sight_guids(entity, now, nearby))
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
    |> MapSet.new()
  end

  defp nearby_line_of_sight_guids(entity, now, nearby) do
    if nearby_line_of_sight_needed?(entity, now) do
      Enum.flat_map(nearby, fn {_kind, entries} -> Enum.map(entries, &elem(&1, 0)) end)
    else
      []
    end
  end

  defp nearby_line_of_sight_needed?(%Mob{internal: %Internal{totem: %Totem{}}}, _now), do: true

  defp nearby_line_of_sight_needed?(
         %Mob{internal: %Internal{pet: nil, in_combat: false, blackboard: blackboard}} = entity,
         now
       ) do
    nearby_targeting_needed?(entity) or
      MobBT.aggro_check_ready?(entity, Blackboard.ensure(blackboard), now)
  end

  defp nearby_line_of_sight_needed?(%Mob{} = entity, _now) do
    nearby_targeting_needed?(entity)
  end

  defp nearby_line_of_sight_needed?(_entity, _now), do: false

  defp nearby_targeting_needed?(%Mob{} = entity) do
    MobSpells.observation_radius(entity) > 0 or
      EventAI.observation_radius(entity) > 0 or
      waypoint_observation_radius(entity) > 0
  end

  defp observed_distances(entries, observations) do
    Enum.flat_map(entries, fn {guid, _distance} ->
      case Map.get(observations, guid) do
        %Observation{distance: distance} when is_number(distance) -> [{guid, distance}]
        _ -> []
      end
    end)
  end

  defp origin(%{internal: %Internal{world: world}, movement_block: %MovementBlock{position: {x, y, z, _o}}}) do
    {world, x, y, z}
  end

  defp origin(_entity), do: nil

  defp distance({world, x, y, z}, {world, tx, ty, tz}) do
    :math.sqrt(:math.pow(tx - x, 2) + :math.pow(ty - y, 2) + :math.pow(tz - z, 2))
  end

  defp distance(_origin, _position), do: nil

  defp random do
    %Random{
      float: &:rand.uniform/0,
      integer: &:rand.uniform/1
    }
  end

  defp navigation(entity, now, perception, random) do
    navigation =
      entity
      |> random_point_requests(now)
      |> Map.new(fn {map_id, anchor, radius} ->
        {{map_id, anchor, radius},
         Aquatic.random_point(map_id, anchor, radius, NavigationResolver.path_options(entity))}
      end)
      |> Navigation.new()

    if Fear.ready?(entity, now) do
      {map_id, anchor, radius} = Fear.destination_request(entity, perception, random)
      %{navigation | fear_point: Aquatic.random_point(map_id, anchor, radius, NavigationResolver.path_options(entity))}
    else
      navigation
    end
  end

  defp random_point_requests(entity, now) do
    wander = if not CreatureMovement.flying?(entity), do: wander_request(entity, now)

    [wander, Confusion.request(entity, now)]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp wander_request(
         %Mob{
           internal: %Internal{
             in_combat: in_combat,
             blackboard: blackboard,
             spawn: %Spawn{movement_type: 1, position: anchor, distance: radius},
             world: world
           }
         },
         now
       )
       when in_combat != true and is_number(radius) and radius > 0 and is_integer(now) do
    blackboard = Blackboard.ensure(blackboard)

    if is_nil(blackboard.navigation.target) and Blackboard.ready_for?(blackboard, :next_wander_at, now) do
      {world.map_id, anchor, radius}
    end
  end

  defp wander_request(_entity, _now), do: nil
end
