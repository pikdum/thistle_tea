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
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Navigation, as: NavigationMemory
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Request
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells, as: MobSpells
  alias ThistleTea.Game.Entity.Logic.AI.EventAI
  alias ThistleTea.Game.Entity.Logic.AI.NavigationIntent
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Server.NavigationResolver
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Waypoint, as: WaypointLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding

  @pet_observation_radius 20.0
  @totem_observation_radius 30.0

  def context(entity, now \\ Time.now(), request \\ %Request{})

  def context(entity, now, %Request{
        actors: actors,
        radius: requested_radius,
        game_object_radius: requested_game_object_radius
      })
      when is_integer(now) and is_list(actors) and is_number(requested_radius) and requested_radius >= 0 and
             is_number(requested_game_object_radius) and requested_game_object_radius >= 0 do
    %Context{
      now: now,
      perception: perception(entity, now, actors, requested_radius, requested_game_object_radius),
      random: random(),
      navigation: navigation(entity, now),
      waypoints: WaypointLoader.context()
    }
  end

  def move_to(entity, destination, opts \\ [], now \\ Time.now()) do
    entity
    |> NavigationIntent.enqueue(destination, opts)
    |> NavigationResolver.resolve(now)
  end

  defp perception(entity, now, observed_guids, requested_radius, requested_game_object_radius) do
    radius = max(observation_radius(entity), requested_radius)
    game_object_radius = max(game_object_observation_radius(entity), requested_game_object_radius)
    nearby = nearby_guids(entity, radius, game_object_radius)

    guids =
      [own_guid(entity) | direct_guids(entity)]
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

  defp auto_repeat_target(%{target_guid: target_guid}), do: target_guid
  defp auto_repeat_target(_auto_repeat), do: nil

  defp own_guid(%{object: %{guid: guid}}) when is_integer(guid) and guid > 0, do: guid
  defp own_guid(_entity), do: nil

  defp threat_guids(threat) when is_map(threat), do: Map.keys(threat)
  defp threat_guids(_threat), do: []

  defp observe(entity, guid, now, line_of_sight_guids) do
    position = World.position(guid, now)

    %Observation{
      guid: guid,
      position: position,
      grounded_position: World.grounded_target_position(guid, now),
      distance: distance(origin(entity), position),
      metadata: Metadata.get(guid),
      moving?: World.moving?(guid, now),
      line_of_sight?: line_of_sight?(entity, guid, line_of_sight_guids)
    }
  end

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

  defp navigation(entity, now) do
    entity
    |> random_point_requests(now)
    |> Map.new(fn {map_id, anchor, radius} ->
      {{map_id, anchor, radius}, Pathfinding.find_random_point_around_circle(map_id, anchor, radius)}
    end)
    |> Navigation.new()
  end

  defp random_point_requests(%Mob{} = entity, now) do
    [wander_request(entity, now), confused_request(entity, now)]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp random_point_requests(_entity, _now), do: []

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

  defp wander_request(%Mob{}, _now), do: nil

  defp confused_request(%Mob{} = entity, now) when is_integer(now) do
    blackboard = Blackboard.ensure(entity.internal.blackboard)

    if confused_wander_ready?(entity, blackboard, now) do
      anchor = confused_anchor(blackboard, entity.movement_block)
      {entity.internal.world.map_id, anchor, MobBT.confused_wander_radius()}
    end
  end

  defp confused_wander_ready?(%Mob{} = entity, %Blackboard{} = blackboard, now) do
    (Aura.has_aura?(entity, :mod_confuse) or Aura.has_aura?(entity, :mod_fear)) and
      is_nil(blackboard.navigation.target) and
      Blackboard.ready_for?(blackboard, :next_confused_at, now)
  end

  defp confused_anchor(%Blackboard{navigation: %NavigationMemory{confused_anchor: {_key, anchor}}}, %MovementBlock{}) do
    anchor
  end

  defp confused_anchor(%Blackboard{}, %MovementBlock{position: {x, y, z, _orientation}}), do: {x, y, z}
end
