defmodule ThistleTea.Game.World.Proximity do
  @moduledoc """
  Proximity aggro by announcement instead of polling.

  Every unit in the world is a member of its visibility cell's proximity key.
  A unit announces itself to the keys within aggro reach when it moves two
  yards, starts a path, appears, or changes how others react to it. Every
  unit that hears the announcement decides for itself in both directions: an
  idle creature that aggroes on sight notices a hostile announcer inside its
  radius, and a unit inside an announcing creature's radius asks that
  creature to notice it. A walking announcer's path becomes one scheduled
  check at the moment of contact, rechecked against the authoritative
  position when it fires.
  """

  alias ThistleTea.Game.Core.Aura.StealthDetection
  alias ThistleTea.Game.Core.Combat.Aggro
  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Combat.Hostility
  alias ThistleTea.Game.Core.Combat.Proximity, as: ProximityCore
  alias ThistleTea.Game.Core.Combat.Proximity.Aggressor
  alias ThistleTea.Game.Core.Combat.Proximity.Announcement
  alias ThistleTea.Game.Core.Combat.Proximity.Path
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.SpatialGrid
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Groups
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.Position.Spline
  alias ThistleTea.Game.World.Reaction

  @group Groups
  @movement_threshold 2.0
  @watched_keys Reaction.actor_keys() ++
                  [
                    :level,
                    :in_combat,
                    :evading?,
                    :charmed_by,
                    :stealthed?,
                    :stealth_skill,
                    :undetectable_until,
                    :invisibility,
                    :invisibility_detection,
                    :stunned?,
                    :detection_range,
                    :detect_range_modifier
                  ]

  defguardp unit?(entity) when is_struct(entity, Mob) or is_struct(entity, Character)

  def key({%WorldRef{map_id: map_id, instance_id: instance_id}, x, y}),
    do: "proximity/#{map_id}/#{instance_id || "world"}/#{x}/#{y}"

  def join(entity, cell) when unit?(entity) do
    :ok = Group.join(@group, key(cell), %{})
    entity
  end

  def join(entity, _cell), do: entity

  def leave(%{internal: %Internal{} = internal} = entity, cell) when unit?(entity) do
    Group.leave(@group, key(cell))
    %{entity | internal: %{internal | proximity: nil}}
  end

  def leave(entity, _cell), do: entity

  def sync(entity, now \\ Time.now())

  def sync(%{object: %{guid: guid}, internal: %Internal{visibility_cell: {_, _, _}} = internal} = entity, now)
      when unit?(entity) and is_integer(guid) do
    case World.position(entity, now) do
      {world, x, y, z} ->
        current = {world, motion(entity, {x, y, z}, now), facts(guid), ProximityCore.aggressor(entity)}

        if changed?(internal.proximity, current) do
          announce(entity, {x, y, z}, now)
          %{entity | internal: %{internal | proximity: current}}
        else
          entity
        end

      nil ->
        entity
    end
  end

  def sync(entity, _now), do: entity

  def announce(entity, position, now) do
    announcement = ProximityCore.announcement(entity, aggro_level(entity), position, now)
    message = {:proximity, announcement}

    announcement.world
    |> SpatialGrid.cells_overlapping(ProximityCore.extent(announcement))
    |> Enum.each(&Group.dispatch(@group, key(&1), message))
  end

  def hear(%{object: %{guid: guid}}, %Announcement{guid: guid}, _now), do: :ignore

  def hear(
        %{internal: %Internal{world: world}} = listener,
        %Announcement{world: world, aggressor: announcer} = announcement,
        now
      ) do
    aggressor = ProximityCore.aggressor(listener)

    with true <- not is_nil(announcer) or not is_nil(aggressor),
         {^world, x, y, z} <- World.position(listener, now) do
      alert(listener, announcement, {x, y, z}, now)
      notice(listener, aggressor, announcement, {x, y, z}, now)
    else
      _ -> :ignore
    end
  end

  def hear(_listener, _announcement, _now), do: :ignore

  def due(%{internal: %Internal{world: world}} = listener, guid, role, now) when is_integer(guid) do
    with {^world, x, y, z} <- World.position(listener, now),
         %Announcement{} = observed <- observe(guid, world, now) do
      case role do
        :alert ->
          alert(listener, observed, {x, y, z}, now)
          :ignore

        :notice ->
          notice(listener, ProximityCore.aggressor(listener), observed, {x, y, z}, now)
      end
    else
      _ -> :ignore
    end
  end

  def due(_listener, _guid, _role, _now), do: :ignore

  defp alert(listener, %Announcement{aggressor: %Aggressor{} = aggressor} = announcement, center, now) do
    radius = ProximityCore.radius(aggressor, aggro_level(listener))

    react(announcement, center, radius, :alert, now, fn distance ->
      target = listener.object.guid
      if engages?(announcement.guid, target, distance, now), do: Entity.aggro_probe(announcement.guid, target)
    end)
  end

  defp alert(_listener, _announcement, _center, _now), do: :ignore

  defp notice(listener, %Aggressor{} = aggressor, %Announcement{} = announcement, center, now) do
    radius = ProximityCore.radius(aggressor, announcement.level)

    react(announcement, center, radius, :notice, now, fn distance ->
      if engages?(listener.object.guid, announcement.guid, distance, now), do: :notice, else: :ignore
    end)
  end

  defp notice(_listener, _aggressor, _announcement, _center, _now), do: :ignore

  defp react(%Announcement{guid: guid} = announcement, center, radius, role, now, act) do
    case ProximityCore.contact(announcement, center, radius, now) do
      {:now, distance} ->
        act.(distance)

      {:after, delay} ->
        Process.send_after(self(), {:proximity_due, guid, role}, delay)
        :ignore

      :never ->
        :ignore
    end
  end

  defp engages?(aggressor_guid, target_guid, distance, now) do
    with %{faction_template: %FactionTemplate{}, level: level} = row when is_integer(level) <-
           Metadata.get(aggressor_guid),
         true <- Map.get(row, :in_combat) != true and Map.get(row, :evading?) != true,
         %{} = target_row <- Metadata.get(target_guid) do
      aggressor = Reaction.actor(Map.put(row, :guid, aggressor_guid))
      target = Reaction.actor(Map.put(target_row, :guid, target_guid))

      Hostility.can_initiate_attack?(aggressor) and Hostility.valid_hostile_target?(aggressor, target) and
        distance <= Aggro.radius(aggressor, actor_level(target)) and
        StealthDetection.detectable?(aggressor, target, distance, now)
    else
      _ -> false
    end
  end

  defp observe(guid, world, now) do
    with {^world, x, y, z} <- World.position(guid, now),
         %{} = row <- Metadata.get(guid) do
      %Announcement{
        guid: guid,
        world: world,
        position: {x, y, z},
        level: actor_level(Reaction.actor(Map.put(row, :guid, guid))),
        path: observed_path(guid, now),
        aggressor: observed_aggressor(row)
      }
    else
      _ -> nil
    end
  end

  defp observed_path(guid, now) do
    case Position.projection(guid) do
      %Spline{falling?: false, started_at: started_at, duration_ms: duration} = spline
      when now <= started_at + duration ->
        %Path{origin: spline.origin, nodes: spline.nodes, started_at: started_at, duration_ms: duration}

      _ ->
        nil
    end
  end

  defp observed_aggressor(%{level: level} = row) when is_integer(level) do
    %Aggressor{
      detection_range: Aggro.detection_range(row),
      level: level,
      modifier: Map.get(row, :detect_range_modifier) || 0
    }
  end

  defp observed_aggressor(_row), do: nil

  defp facts(guid) do
    case Metadata.query(guid, @watched_keys) do
      %{} = facts -> Map.put(facts, :guid, guid)
      nil -> %{guid: guid}
    end
  end

  defp motion(entity, position, now) do
    case ProximityCore.path(entity, now) do
      %Path{started_at: started_at} -> {:path, started_at}
      nil -> {:at, position}
    end
  end

  defp changed?({world, from, facts, aggressor}, {world, to, facts, aggressor}) do
    (not is_nil(aggressor) or Hostility.proximity_target?(facts)) and moved?(from, to)
  end

  defp changed?(previous, current), do: previous != current

  defp moved?({:at, {fx, fy, _fz}}, {:at, {tx, ty, _tz}}) do
    dx = tx - fx
    dy = ty - fy
    dx * dx + dy * dy >= @movement_threshold * @movement_threshold
  end

  defp moved?(from, to), do: from != to

  defp aggro_level(%Mob{unit: %Unit{charmed_by: charmer}, internal: %Internal{pet: pet}} = entity)
       when (is_integer(charmer) and charmer > 0) or not is_nil(pet) do
    entity |> Reaction.actor() |> actor_level()
  end

  defp aggro_level(%{unit: %Unit{level: level}}), do: level || 1

  defp actor_level(%{owner: %{level: level}}) when is_integer(level), do: level
  defp actor_level(%{level: level}) when is_integer(level), do: level
  defp actor_level(_actor), do: 1
end
