defmodule ThistleTea.Game.Core.Combat.Proximity do
  @moduledoc """
  Pure rules for proximity aggro by announcement.

  A unit announces itself when it moves, appears, or changes how others react
  to it: where it stands, the path it is walking, the level aggro radii are
  judged against, for an idle creature that aggroes on sight, the detection
  it notices targets with, and, for a civilian that calls the guards, the
  range it watches for enemies. An announcement reaches every unit that
  could care: the widest aggro radius or out-of-combat line-of-sight event
  range. Every unit that hears one decides for itself in both directions,
  whether it notices the announcer and whether the announcer should notice it.
  `contact/4` turns a walking announcer's path into the moment it first comes
  within a radius, so a listener schedules one check instead of polling.

  A hidden announcer's position decides who can see it, so a hidden unit
  walking a path announces itself again every `movement_step/0` yards, and a
  unit that is undetectable for a while announces itself again the moment
  that ends. `refresh_at/4` is the next of those moments.
  """

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.Combat.Aggro
  alias ThistleTea.Game.Core.Creature.GuardCall
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Movement

  @contact_margin_ms 50
  @max_path_extent 250.0
  @max_sight_range 80.0
  @movement_step 2.0

  defmodule Path do
    @moduledoc false
    @enforce_keys [:origin, :nodes, :started_at, :duration_ms]
    defstruct [:origin, :nodes, :started_at, :duration_ms]
  end

  defmodule Aggressor do
    @moduledoc false
    @enforce_keys [:detection_range, :level, :modifier]
    defstruct [:detection_range, :level, :modifier]
  end

  defmodule Announcement do
    @moduledoc false
    @enforce_keys [:guid, :world, :position, :level]
    defstruct [:guid, :world, :position, :level, :path, :aggressor, :watch, :incarnation_id, hidden?: false]
  end

  def announcement(
        %{object: %{guid: guid}, internal: %Internal{world: world}} = entity,
        level,
        {_x, _y, _z} = position,
        now,
        hidden? \\ false
      )
      when is_integer(guid) and is_integer(level) and is_integer(now) and is_boolean(hidden?) do
    %Announcement{
      guid: guid,
      world: world,
      position: position,
      level: level,
      path: path(entity, now),
      aggressor: aggressor(entity),
      watch: watch(entity),
      incarnation_id: incarnation(entity),
      hidden?: hidden?
    }
  end

  def movement_step, do: @movement_step

  defp incarnation(%{internal: %Internal{spawn: %{incarnation_id: id}}}), do: id
  defp incarnation(_entity), do: nil

  def path(entity, now) do
    path = walking_path(entity, now)
    if path && short?(path), do: path
  end

  def refresh_at(entity, undetectable_until, hidden?, now) when is_boolean(hidden?) and is_integer(now) do
    [expiry(undetectable_until, now), if(hidden?, do: step_at(walking_path(entity, now), now))]
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> nil end)
  end

  defp walking_path(
         %{
           internal: %Internal{movement_start_time: started_at, movement_start_position: origin},
           movement_block: %MovementBlock{spline_nodes: [_ | _] = nodes, duration: duration}
         } = entity,
         now
       )
       when is_integer(started_at) and is_tuple(origin) and is_integer(duration) and duration > 0 do
    if Movement.moving?(entity, now) and not Movement.falling?(entity),
      do: %Path{origin: origin, nodes: nodes, started_at: started_at, duration_ms: duration}
  end

  defp walking_path(_entity, _now), do: nil

  defp expiry(until, now) when is_integer(until) and until > now, do: until
  defp expiry(_until, _now), do: nil

  defp step_at(%Path{origin: origin, nodes: nodes, started_at: started_at, duration_ms: duration}, now) do
    total = path_length([origin | nodes])
    at = if total > 0, do: now + ceil(@movement_step * duration / total)
    if at && at < started_at + duration, do: at
  end

  defp step_at(nil, _now), do: nil

  def aggressor(
        %Mob{
          unit: %Unit{level: level, charmed_by: charmed_by},
          internal: %Internal{pet: nil, totem: nil, in_combat: false, blackboard: blackboard}
        } = mob
      )
      when charmed_by in [nil, 0] do
    if not Entity.dead?(mob) and not evading?(blackboard) and Mob.proximity_aggro?(mob) and
         Aggro.search_radius(mob) > 0 do
      %Aggressor{detection_range: Aggro.detection_range(mob), level: level || 1, modifier: Aggro.modifier(mob)}
    end
  end

  def aggressor(_entity), do: nil

  def watch(%Mob{} = mob), do: GuardCall.watch_range(mob)
  def watch(_entity), do: nil

  def radius(%Aggressor{detection_range: range, level: level, modifier: modifier}, target_level),
    do: Aggro.radius_for(range, level, target_level || 1, modifier)

  def reach(%Announcement{aggressor: %Aggressor{detection_range: range, modifier: modifier}} = announcement),
    do: Enum.max([Aggro.max_radius(), @max_sight_range, Aggro.reach(range, modifier), announcement.watch || 0.0])

  def reach(%Announcement{} = announcement),
    do: Enum.max([Aggro.max_radius(), @max_sight_range, announcement.watch || 0.0])

  def extent(%Announcement{} = announcement) do
    reach = reach(announcement)
    points = points(announcement)
    {min_x, max_x} = points |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    {min_y, max_y} = points |> Enum.map(&elem(&1, 1)) |> Enum.min_max()
    {min_x - reach, min_y - reach, max_x + reach, max_y + reach}
  end

  def contact(%Announcement{path: %Path{} = path}, center, radius, now) when is_integer(now) do
    path_contact(path, center, radius, now)
  end

  def contact(%Announcement{position: position}, center, radius, _now), do: stationary_contact(position, center, radius)

  defp points(%Announcement{position: position, path: %Path{origin: origin, nodes: nodes}}),
    do: [position, origin | nodes]

  defp points(%Announcement{position: position}), do: [position]

  defp short?(%Path{origin: origin, nodes: nodes}) do
    {min_x, max_x} = [origin | nodes] |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    {min_y, max_y} = [origin | nodes] |> Enum.map(&elem(&1, 1)) |> Enum.min_max()
    max(max_x - min_x, max_y - min_y) <= @max_path_extent
  end

  defp evading?(%Blackboard{navigation: %{returning_home?: true}}), do: true
  defp evading?(_blackboard), do: false

  defp stationary_contact(position, center, radius) do
    distance = Math.distance(position, center)
    if distance <= radius, do: {:now, distance}, else: :never
  end

  defp path_contact(
         %Path{origin: origin, nodes: nodes, started_at: started_at, duration_ms: duration},
         center,
         radius,
         now
       ) do
    points = [origin | nodes]
    total = path_length(points)
    elapsed = min(max(now - started_at, 0), duration)

    if total <= 0 or elapsed >= duration do
      stationary_contact(List.last(points), center, radius)
    else
      travelled = total * elapsed / duration

      case entry_distance(points, travelled, center, radius) do
        nil ->
          :never

        distance when distance <= 0 ->
          {:now, Math.distance(Movement.position_at(origin, nodes, duration, elapsed), center)}

        distance ->
          {:after, ceil(distance * duration / total) + @contact_margin_ms}
      end
    end
  end

  defp path_length([first | rest]) do
    rest
    |> Enum.reduce({first, 0.0}, fn point, {previous, length} -> {point, length + Math.distance(previous, point)} end)
    |> elem(1)
  end

  defp entry_distance([start | rest], travelled, center, radius) do
    rest
    |> Enum.reduce_while({start, 0.0}, &segment_entry_distance(&1, &2, travelled, center, radius))
    |> case do
      {_point, _walked} -> nil
      distance -> distance
    end
  end

  defp segment_entry_distance(finish, {previous, walked}, travelled, center, radius) do
    length = Math.distance(previous, finish)
    segment_end = walked + length

    if length <= 0 or travelled >= segment_end do
      {:cont, {finish, segment_end}}
    else
      offset = max(travelled - walked, 0.0)
      from = lerp(previous, finish, offset / length)

      case segment_entry(from, finish, center, radius) do
        nil -> {:cont, {finish, segment_end}}
        fraction -> {:halt, walked + offset - travelled + fraction * (length - offset)}
      end
    end
  end

  defp segment_entry({x1, y1, z1}, {x2, y2, z2}, {cx, cy, cz}, radius) do
    {dx, dy, dz} = {x2 - x1, y2 - y1, z2 - z1}
    {fx, fy, fz} = {x1 - cx, y1 - cy, z1 - cz}
    c = fx * fx + fy * fy + fz * fz - radius * radius

    if c <= 0 do
      0.0
    else
      a = dx * dx + dy * dy + dz * dz
      b = 2.0 * (fx * dx + fy * dy + fz * dz)
      discriminant = b * b - 4.0 * a * c
      if a > 0 and discriminant >= 0, do: entry_fraction(a, b, discriminant)
    end
  end

  defp entry_fraction(a, b, discriminant) do
    fraction = (-b - :math.sqrt(discriminant)) / (2.0 * a)
    if fraction >= 0.0 and fraction <= 1.0, do: fraction
  end

  defp lerp({x1, y1, z1}, {x2, y2, z2}, t), do: {x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, z1 + (z2 - z1) * t}
end
