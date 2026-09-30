defmodule ThistleTea.Game.World.Proximity do
  @moduledoc """
  Proximity aggro and stealth sight by announcement instead of polling.

  Every unit in the world is a member of its visibility cell's proximity key.
  A unit announces itself to the keys within aggro reach when it moves two
  yards, starts a path, appears, or changes how others react to it. Every
  unit that hears the announcement decides for itself in both directions: an
  idle creature that aggroes on sight notices a hostile announcer inside its
  radius, and a unit inside an announcing creature's radius asks that
  creature to notice it. A creature with an out-of-combat line-of-sight
  EventAI event also wakes for any announcer within that event's range. A
  walking announcer's path becomes one scheduled check at the moment of
  contact, rechecked against the authoritative position when it fires.

  Stealthed units and stealthed traps are also listed under their cell's
  hidden key, so a viewer that moves or turns re-checks only them. A
  stealthed unit's announcements are marked hidden so the viewers that hear
  them re-check it. It announces again every two yards while walking a path,
  and a unit that is undetectable for a while announces again when that
  ends. A unit whose reaction facts change tells the traps it owns through
  its owned key, since whether an enemy sees a trap depends on its owner.
  """

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.EventAI
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
  alias ThistleTea.Game.Core.Entity.Component.Internal.Trap
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
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
  alias ThistleTea.Game.World.Proximity.Checks
  alias ThistleTea.Game.World.Reaction

  @group Groups
  @watched_keys Reaction.actor_keys() ++
                  StealthDetection.fact_keys() ++
                  [
                    :level,
                    :in_combat,
                    :evading?,
                    :charmed_by,
                    :detection_range,
                    :detect_range_modifier
                  ]

  defguardp unit?(entity) when is_struct(entity, Mob) or is_struct(entity, Character)

  defguardp stealthed_trap?(entity)
            when is_struct(entity, GameObject) and is_struct(entity.internal.trap, Trap) and
                   entity.internal.trap.stealthed? == true

  def key({%WorldRef{map_id: map_id, instance_id: instance_id}, x, y}),
    do: "proximity/#{map_id}/#{instance_id || "world"}/#{x}/#{y}"

  def hidden_key({%WorldRef{map_id: map_id, instance_id: instance_id}, x, y}),
    do: "hidden/#{map_id}/#{instance_id || "world"}/#{x}/#{y}"

  def owned_key(guid) when is_integer(guid), do: "owned/#{guid}"

  def hidden_members(cells) do
    cells
    |> Enum.flat_map(&Group.members(@group, hidden_key(&1)))
    |> Enum.map(fn {_pid, %{guid: guid}} -> guid end)
    |> Enum.uniq()
  end

  def join(%{object: %{guid: guid}} = entity, cell) when unit?(entity) do
    :ok = Group.join(@group, key(cell), %{})
    list_hidden(entity, match?(%{stealthed?: true}, Metadata.query(guid, [:stealthed?])), cell)
  end

  def join(entity, cell) when stealthed_trap?(entity) do
    case entity.game_object.created_by do
      owner when is_integer(owner) and owner > 0 -> :ok = Group.join(@group, owned_key(owner), %{})
      _unowned -> :ok
    end

    list_hidden(entity, true, cell)
  end

  def join(entity, _cell), do: entity

  def leave(%{internal: %Internal{}} = entity, cell) when unit?(entity) do
    Group.leave(@group, key(cell))

    entity
    |> Checks.clear()
    |> then(&%{&1 | internal: %{&1.internal | proximity: nil}})
    |> list_hidden(false, cell)
  end

  def leave(entity, cell) when stealthed_trap?(entity) do
    case entity.game_object.created_by do
      owner when is_integer(owner) and owner > 0 -> Group.leave(@group, owned_key(owner))
      _unowned -> :ok
    end

    list_hidden(entity, false, cell)
  end

  def leave(entity, _cell), do: entity

  def sync(entity, now \\ Time.now()), do: sync(entity, now, false)

  def refresh(%{internal: %Internal{proximity_refresh: {ref, _at}} = internal} = entity, ref, now) do
    sync(%{entity | internal: %{internal | proximity_refresh: nil}}, now, true)
  end

  def refresh(entity, _ref, _now), do: entity

  def reaction_changed?(%{internal: %Internal{proximity: previous}}, %{internal: %Internal{proximity: current}}),
    do: reaction_changed?(previous, current)

  def reaction_changed?({_world, _motion, previous, _aggressor}, {_, _, current, _}),
    do: Map.take(previous, Reaction.actor_keys()) != Map.take(current, Reaction.actor_keys())

  def reaction_changed?(_previous, _current), do: false

  defp sync(
         %{object: %{guid: guid}, internal: %Internal{visibility_cell: {_, _, _} = cell} = internal} = entity,
         now,
         forced?
       )
       when unit?(entity) and is_integer(guid) do
    case World.position(entity, now) do
      {world, x, y, z} ->
        facts = facts(guid)
        hidden? = Map.get(facts, :stealthed?) == true
        current = {world, motion(entity, {x, y, z}, now), facts, ProximityCore.aggressor(entity)}
        entity = list_hidden(entity, hidden?, cell)
        entity = if Map.get(facts, :alive?) == false, do: Checks.clear(entity), else: entity

        if forced? or changed?(internal.proximity, current),
          do: publish(entity, current, {x, y, z}, hidden? or forced?, now),
          else: entity

      nil ->
        entity
    end
  end

  defp sync(entity, _now, _forced?), do: entity

  defp publish(
         %{object: %{guid: guid}, internal: internal} = entity,
         {_, _, facts, _} = current,
         position,
         hidden?,
         now
       ) do
    if reaction_changed?(internal.proximity, current),
      do: Group.dispatch(@group, owned_key(guid), {:owner_reaction_changed, guid})

    refresh_at =
      ProximityCore.refresh_at(entity, Map.get(facts, :undetectable_until), Map.get(facts, :stealthed?) == true, now)

    %{entity | internal: %{internal | proximity: current}}
    |> announce(position, now, hidden?)
    |> schedule_refresh(refresh_at, now)
  end

  defp announce(entity, position, now, hidden?) do
    announcement = ProximityCore.announcement(entity, aggro_level(entity), position, now, hidden?)
    message = {:proximity, announcement}

    announcement.world
    |> SpatialGrid.cells_overlapping(ProximityCore.extent(announcement))
    |> Enum.each(&Group.dispatch(@group, key(&1), message))

    entity
  end

  defp schedule_refresh(%{internal: %Internal{proximity_refresh: {_ref, at}}} = entity, at, _now), do: entity

  defp schedule_refresh(%{internal: %Internal{proximity_refresh: refresh} = internal} = entity, at, now) do
    with {ref, _at} <- refresh, do: :erlang.cancel_timer(ref)
    refresh = if at, do: {:erlang.start_timer(max(at - now, 0) + 1, self(), :proximity_refresh), at}
    %{entity | internal: %{internal | proximity_refresh: refresh}}
  end

  defp list_hidden(%{internal: %Internal{hidden_cell: cell}} = entity, true, cell), do: entity
  defp list_hidden(%{internal: %Internal{hidden_cell: nil}} = entity, false, _cell), do: entity

  defp list_hidden(%{object: %{guid: guid}, internal: %Internal{} = internal} = entity, hidden?, cell) do
    if internal.hidden_cell, do: Group.leave(@group, hidden_key(internal.hidden_cell))
    if hidden?, do: :ok = Group.join(@group, hidden_key(cell), %{guid: guid})
    %{entity | internal: %{internal | hidden_cell: if(hidden?, do: cell)}}
  end

  def hear(%{object: %{guid: guid}} = listener, %Announcement{guid: guid}, _now), do: {listener, :ignore}

  def hear(
        %{internal: %Internal{world: world}} = listener,
        %Announcement{world: world, aggressor: announcer} = announcement,
        now
      ) do
    aggressor = ProximityCore.aggressor(listener)
    sight_range = sight_range(listener, now)

    with true <- not is_nil(announcer) or not is_nil(aggressor) or sight_range > 0,
         {^world, x, y, z} <- World.position(listener, now) do
      {listener, _result} = alert(listener, announcement, {x, y, z}, now)

      case notice(listener, aggressor, announcement, {x, y, z}, now) do
        {listener, :notice} -> {Checks.cancel(listener, announcement.guid, :sight), :notice}
        {listener, :ignore} -> sight(listener, sight_range, announcement, {x, y, z}, now)
      end
    else
      _ -> {listener, :ignore}
    end
  end

  def hear(listener, _announcement, _now), do: {listener, :ignore}

  def due(%{internal: %Internal{world: world}} = listener, guid, role, ref, now) when is_integer(guid) do
    {listener, current?} = Checks.take(listener, guid, role, ref)

    with true <- current?,
         {^world, x, y, z} <- World.position(listener, now),
         %Announcement{} = observed <- observed(guid, world, now) do
      case role do
        :alert ->
          alert(listener, observed, {x, y, z}, now)

        :notice ->
          notice(listener, ProximityCore.aggressor(listener), observed, {x, y, z}, now)

        :sight ->
          sight(listener, sight_range(listener, now), observed, {x, y, z}, now)
      end
    else
      _ -> {listener, :ignore}
    end
  end

  def due(listener, _guid, _role, _ref, _now), do: {listener, :ignore}

  defp alert(listener, %Announcement{aggressor: %Aggressor{} = aggressor} = announcement, center, now) do
    radius = ProximityCore.radius(aggressor, aggro_level(listener))

    react(listener, announcement, center, radius, :alert, now, fn distance ->
      target = listener.object.guid
      if engages?(announcement.guid, target, distance, now), do: Entity.aggro_probe(announcement.guid, target)
      :ignore
    end)
  end

  defp alert(listener, announcement, _center, _now), do: {Checks.cancel(listener, announcement.guid, :alert), :ignore}

  defp notice(listener, %Aggressor{} = aggressor, %Announcement{} = announcement, center, now) do
    radius = ProximityCore.radius(aggressor, announcement.level)

    react(listener, announcement, center, radius, :notice, now, fn distance ->
      if engages?(listener.object.guid, announcement.guid, distance, now), do: :notice, else: :ignore
    end)
  end

  defp notice(listener, _aggressor, announcement, _center, _now),
    do: {Checks.cancel(listener, announcement.guid, :notice), :ignore}

  defp sight(listener, range, %Announcement{} = announcement, center, now) when range > 0,
    do: react(listener, announcement, center, range, :sight, now, fn _distance -> :sight end)

  defp sight(listener, _range, announcement, _center, _now),
    do: {Checks.cancel(listener, announcement.guid, :sight), :ignore}

  defp sight_range(%Mob{internal: %Internal{blackboard: blackboard}} = mob, now),
    do: EventAI.ooc_los_radius(mob, Blackboard.ensure(blackboard), now)

  defp sight_range(_listener, _now), do: 0.0

  defp react(listener, %Announcement{guid: guid} = announcement, center, radius, role, now, act) do
    case ProximityCore.contact(announcement, center, radius, now) do
      {:now, distance} ->
        {Checks.cancel(listener, guid, role), act.(distance)}

      {:after, delay} ->
        {Checks.schedule(listener, announcement, role, now + delay, now), :ignore}

      :never ->
        {Checks.cancel(listener, guid, role), :ignore}
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

  defp observed(guid, world, now) do
    with {^world, x, y, z} <- World.position(guid, now),
         %{} = row <- Metadata.get(guid) do
      %Announcement{
        guid: guid,
        world: world,
        incarnation_id: Map.get(row, :incarnation_id),
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
    step = ProximityCore.movement_step()
    dx * dx + dy * dy >= step * step
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
