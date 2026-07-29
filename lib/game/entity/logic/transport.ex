defmodule ThistleTea.Game.Entity.Logic.Transport do
  @moduledoc """
  Pure construction and interpolation for VMangos-compatible transport routes.
  """

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Transport
  alias ThistleTea.Game.Entity.Data.Transport.AnimationFrame
  alias ThistleTea.Game.Entity.Data.Transport.Keyframe
  alias ThistleTea.Game.Entity.Data.Transport.Pose
  alias ThistleTea.Game.Entity.Data.Transport.Spline
  alias ThistleTea.Game.Math

  @map_transition_flag 0x1
  @stop_flag 0x2
  @spline_length_steps 3
  @two_pi 2 * :math.pi()

  defguardp valid_ship_path(entry, path_id, nodes)
            when is_integer(entry) and is_integer(path_id) and is_list(nodes) and length(nodes) >= 3

  defguardp valid_ship_motion(move_speed, accel_rate)
            when is_number(move_speed) and move_speed > 0 and is_number(accel_rate) and accel_rate > 0

  def build_ship(entry, name, path_id, nodes, move_speed, accel_rate, period_ms)
      when valid_ship_path(entry, path_id, nodes) and valid_ship_motion(move_speed, accel_rate) do
    accel_time = move_speed / accel_rate
    accel_distance = 0.5 * move_speed * move_speed / accel_rate

    keyframes =
      nodes
      |> initial_keyframes()
      |> attach_splines()
      |> attach_stop_distances()
      |> attach_travel_times(move_speed, accel_rate, accel_distance)
      |> attach_schedule()
      |> apply_period(period_ms)
      |> mark_refresh_frame(path_id)

    %Transport{
      entry: entry,
      name: name,
      kind: :ship,
      period_ms: route_period(keyframes, period_ms),
      move_speed: move_speed * 1.0,
      accel_rate: accel_rate * 1.0,
      accel_time: accel_time,
      accel_distance: accel_distance,
      path_id: path_id,
      keyframes: keyframes,
      maps: MapSet.new(keyframes, & &1.map_id)
    }
  end

  def build_animation(entry, name, frames) when is_integer(entry) and is_list(frames) and frames != [] do
    frames =
      frames
      |> Enum.sort_by(&frame_value(&1, :time_ms))
      |> Enum.map(fn frame ->
        %AnimationFrame{
          time_ms: frame_value(frame, :time_ms),
          position: frame_value(frame, :position),
          sequence: frame_value(frame, :sequence)
        }
      end)

    %Transport{
      entry: entry,
      name: name,
      kind: :animation,
      period_ms: frames |> List.last() |> Map.fetch!(:time_ms),
      animation_frames: frames
    }
  end

  def pose_at(%Transport{kind: :ship, period_ms: period_ms, keyframes: keyframes} = route, elapsed_ms)
      when is_integer(elapsed_ms) and period_ms > 0 do
    progress_ms = Integer.mod(elapsed_ms, period_ms)
    {frame_index, frame} = active_keyframe(keyframes, progress_ms)

    if stopped?(frame, progress_ms) do
      %Pose{
        map_id: frame.map_id,
        position: with_orientation(frame.position, frame.initial_orientation),
        progress_ms: progress_ms,
        frame_index: frame_index
      }
    else
      moving_pose(route, frame, frame_index, progress_ms)
    end
  end

  def pose_at(
        %Transport{kind: :animation, period_ms: period_ms, animation_frames: frames},
        elapsed_ms,
        stationary_position,
        rotation
      )
      when is_integer(elapsed_ms) and period_ms > 0 and tuple_size(stationary_position) == 4 and
             tuple_size(rotation) == 4 do
    progress_ms = Integer.mod(elapsed_ms, period_ms)
    {frame_index, previous, following} = animation_segment(frames, progress_ms)
    local_position = animation_position(previous, following, progress_ms)
    {x, y, z} = rotate_animation_position(local_position, rotation)
    {base_x, base_y, base_z, orientation} = stationary_position

    %Pose{
      position: {base_x + x, base_y - y, base_z + z, orientation},
      progress_ms: progress_ms,
      frame_index: frame_index,
      moving?: previous.position != following.position
    }
  end

  def passenger_world_position({local_x, local_y, local_z, local_orientation}, {x, y, z, orientation}) do
    cos_orientation = :math.cos(orientation)
    sin_orientation = :math.sin(orientation)

    {
      x + local_x * cos_orientation - local_y * sin_orientation,
      y + local_y * cos_orientation + local_x * sin_orientation,
      z + local_z,
      normalize_orientation(orientation + local_orientation)
    }
  end

  def passenger_local_position({world_x, world_y, world_z, world_orientation}, {x, y, z, orientation}) do
    dx = world_x - x
    dy = world_y - y
    cos_orientation = :math.cos(orientation)
    sin_orientation = :math.sin(orientation)

    {
      dx * cos_orientation + dy * sin_orientation,
      dy * cos_orientation - dx * sin_orientation,
      world_z - z,
      normalize_orientation(world_orientation - orientation)
    }
  end

  def valid_passenger_position?({x, y, z, orientation}) do
    Enum.all?([x, y, z, orientation], &is_number/1) and
      abs(x) <= 250 and abs(y) <= 250 and abs(z) <= 100
  end

  def valid_passenger_position?(_position), do: false

  defp initial_keyframes(nodes) do
    extended_points = orientation_points(nodes)
    final_index = length(nodes) - 2

    {keyframes, _map_change?} =
      Enum.reduce(1..final_index, {[], false}, fn index, {keyframes, map_change?} ->
        node = Enum.at(nodes, index)
        next_node = Enum.at(nodes, index + 1)

        cond do
          map_change? ->
            {keyframes, false}

          transition_node?(node, next_node) ->
            {mark_last_teleport(keyframes), true}

          true ->
            derivative = spline_derivative(extended_points, index + 1, 0.0)

            frame = %Keyframe{
              node_index: frame_value(node, :node_index),
              map_id: frame_value(node, :map_id),
              position: frame_value(node, :position),
              delay_seconds: frame_value(node, :delay),
              initial_orientation:
                normalize_orientation(:math.atan2(elem(derivative, 1), elem(derivative, 0)) + :math.pi()),
              teleport?: false,
              refresh?: false,
              stop?: frame_value(node, :flags) == @stop_flag,
              distance_from_previous: -1.0,
              distance_since_stop: -1.0,
              distance_until_stop: -1.0,
              time_from: 0.0,
              time_to: 0.0,
              arrive_at_ms: 0,
              depart_at_ms: 0,
              next_distance_from_previous: 0.0,
              next_arrive_at_ms: 0
            }

            {keyframes ++ [frame], false}
        end
      end)

    mark_last_teleport(keyframes)
  end

  defp orientation_points(nodes) do
    points = Enum.map(nodes, &frame_value(&1, :position))
    first = hd(points)
    second = Enum.at(points, 1)
    last = List.last(points)
    previous = Enum.at(points, -2)
    before = lerp(first, second, -0.2)
    after_point = lerp(last, previous, -0.2)
    final_point = lerp(after_point, last, -1.0)
    [before | points] ++ [after_point, final_point]
  end

  defp transition_node?(node, next_node) do
    (frame_value(node, :flags) &&& @map_transition_flag) != 0 or
      frame_value(node, :map_id) != frame_value(next_node, :map_id)
  end

  defp mark_last_teleport([]), do: []

  defp mark_last_teleport(keyframes) do
    List.update_at(keyframes, -1, &%{&1 | teleport?: true})
  end

  defp attach_splines(keyframes) do
    spline_points = Enum.map(keyframes, & &1.position)
    last_index = length(keyframes) - 1

    {keyframes, _start_index} =
      Enum.reduce(1..last_index, {keyframes, 0}, fn index, {frames, start_index} ->
        previous = Enum.at(frames, index - 1)

        if previous.teleport? or index + 1 == length(frames) do
          close_spline_segment(frames, spline_points, start_index, index, previous.teleport?)
        else
          {frames, start_index}
        end
      end)

    first_distance = keyframes |> hd() |> Map.fetch!(:distance_from_previous)
    List.update_at(keyframes, -1, &%{&1 | next_distance_from_previous: first_distance})
  end

  defp close_spline_segment(frames, spline_points, start_index, index, teleport?) do
    extra = if teleport?, do: 0, else: 1
    count = index - start_index + extra
    spline = spline_points |> Enum.slice(start_index, count) |> new_spline()
    end_index = index + extra - 1

    frames =
      Enum.reduce(indexes(start_index, end_index), frames, fn frame_index, acc ->
        spline_index = frame_index - start_index + 1
        distance = spline_length(spline, frame_index - start_index, frame_index + 1 - start_index)

        acc
        |> List.update_at(
          frame_index,
          &%{&1 | spline: spline, spline_index: spline_index, distance_from_previous: distance}
        )
        |> put_previous_next_distance(frame_index, distance)
      end)

    frames =
      if teleport? do
        frames
        |> List.update_at(
          index,
          &%{&1 | spline: spline, spline_index: index - start_index + 1, distance_from_previous: 0.0}
        )
        |> List.update_at(index - 1, &%{&1 | next_distance_from_previous: 0.0})
      else
        frames
      end

    {frames, index}
  end

  defp put_previous_next_distance(frames, 0, _distance), do: frames

  defp put_previous_next_distance(frames, frame_index, distance) do
    List.update_at(frames, frame_index - 1, &%{&1 | next_distance_from_previous: distance})
  end

  defp indexes(first, last) when first <= last, do: first..last
  defp indexes(_first, _last), do: []

  defp attach_stop_distances(keyframes) do
    stop_indexes =
      keyframes
      |> Enum.with_index()
      |> Enum.filter(fn {frame, _index} -> frame.stop? end)
      |> Enum.map(&elem(&1, 1))

    first_stop = List.first(stop_indexes) || 0
    last_stop = List.last(stop_indexes) || 0
    count = length(keyframes)

    {keyframes, _distance} =
      Enum.reduce(0..(count - 1), {keyframes, 0.0}, fn offset, {frames, distance} ->
        index = Integer.mod(offset + last_stop, count)
        frame = Enum.at(frames, index)
        distance = if frame.stop? or index == last_stop, do: 0.0, else: distance + frame.distance_from_previous
        {List.update_at(frames, index, &%{&1 | distance_since_stop: distance}), distance}
      end)

    {keyframes, _distance} =
      Enum.reduce((count - 1)..0//-1, {keyframes, 0.0}, fn offset, {frames, distance} ->
        index = Integer.mod(offset + first_stop, count)
        next_index = Integer.mod(index + 1, count)
        distance = distance + Enum.at(frames, next_index).distance_from_previous
        frames = List.update_at(frames, index, &%{&1 | distance_until_stop: distance})
        distance = if Enum.at(frames, index).stop? or index == first_stop, do: 0.0, else: distance
        {frames, distance}
      end)

    {keyframes, first_stop, last_stop}
  end

  defp attach_travel_times({keyframes, first_stop, last_stop}, speed, accel_rate, accel_distance) do
    keyframes =
      Enum.map(keyframes, fn frame ->
        %{frame | time_to: time_until_stop(frame, speed, accel_rate, accel_distance)}
      end)

    count = length(keyframes)

    {keyframes, _segment_time} =
      Enum.reduce(0..(count - 1), {keyframes, 0.0}, fn offset, {frames, segment_time} ->
        index = Integer.mod(offset + last_stop, count)
        frame = Enum.at(frames, index)
        segment_time = if frame.stop? or index == last_stop, do: frame.time_to, else: segment_time
        {List.update_at(frames, index, &%{&1 | time_from: segment_time - frame.time_to}), segment_time}
      end)

    {keyframes, first_stop}
  end

  defp time_until_stop(frame, speed, accel_rate, accel_distance) do
    total_distance = frame.distance_since_stop + frame.distance_until_stop

    cond do
      total_distance < 2 * accel_distance and frame.distance_since_stop < frame.distance_until_stop ->
        2.0 * :math.sqrt(total_distance / accel_rate) -
          :math.sqrt(2.0 * frame.distance_since_stop / accel_rate)

      total_distance < 2 * accel_distance ->
        :math.sqrt(2.0 * frame.distance_until_stop / accel_rate)

      frame.distance_since_stop < accel_distance ->
        total_distance / speed + speed / accel_rate -
          :math.sqrt(2.0 * frame.distance_since_stop / accel_rate)

      frame.distance_until_stop < accel_distance ->
        :math.sqrt(2.0 * frame.distance_until_stop / accel_rate)

      true ->
        frame.distance_until_stop / speed + 0.5 * speed / accel_rate
    end
  end

  defp attach_schedule({keyframes, _first_stop}) do
    first = hd(keyframes)
    initial_path_time = if first.stop?, do: frame_delay_seconds(first), else: 0.0

    keyframes =
      List.update_at(keyframes, 0, fn frame ->
        %{frame | arrive_at_ms: 0, depart_at_ms: if(frame.stop?, do: trunc(initial_path_time * 1_000), else: 0)}
      end)

    {keyframes, _path_time} =
      Enum.reduce(1..(length(keyframes) - 1), {keyframes, initial_path_time}, &schedule_frame/2)

    last_departure = keyframes |> List.last() |> Map.fetch!(:depart_at_ms)
    List.update_at(keyframes, -1, &%{&1 | next_arrive_at_ms: last_departure})
  end

  defp schedule_frame(index, {frames, path_time}) do
    previous = Enum.at(frames, index - 1)
    frame = Enum.at(frames, index)
    path_time = path_time + previous.time_to

    if frame.stop? do
      arrive_at_ms = trunc(path_time * 1_000)

      frames =
        frames
        |> List.update_at(index - 1, &%{&1 | next_arrive_at_ms: arrive_at_ms})
        |> List.update_at(index, fn current ->
          %{
            current
            | arrive_at_ms: arrive_at_ms,
              depart_at_ms: trunc((path_time + frame_delay_seconds(frame)) * 1_000)
          }
        end)

      {frames, path_time + frame_delay_seconds(frame)}
    else
      path_time = path_time - frame.time_to
      arrive_at_ms = trunc(path_time * 1_000)

      frames =
        frames
        |> List.update_at(index - 1, &%{&1 | next_arrive_at_ms: arrive_at_ms})
        |> List.update_at(index, &%{&1 | arrive_at_ms: arrive_at_ms, depart_at_ms: arrive_at_ms})

      {frames, path_time}
    end
  end

  defp frame_delay_seconds(%Keyframe{delay_seconds: delay}), do: delay * 1.0

  defp apply_period(keyframes, period_ms) when is_integer(period_ms) and period_ms > 0 do
    List.update_at(keyframes, -1, &%{&1 | depart_at_ms: period_ms})
  end

  defp apply_period(keyframes, _period_ms), do: keyframes

  defp route_period(_keyframes, period_ms) when is_integer(period_ms) and period_ms > 0, do: period_ms
  defp route_period(keyframes, _period_ms), do: keyframes |> List.last() |> Map.fetch!(:depart_at_ms)

  defp mark_refresh_frame(keyframes, path_id) when path_id in [293, 303] and length(keyframes) > 12 do
    List.update_at(keyframes, 12, &%{&1 | refresh?: true})
  end

  defp mark_refresh_frame(keyframes, _path_id), do: keyframes

  defp active_keyframe(keyframes, progress_ms) do
    keyframes
    |> Enum.with_index()
    |> Enum.find(fn {frame, _index} ->
      stopped?(frame, progress_ms) or
        (progress_ms >= frame.depart_at_ms and progress_ms < frame.next_arrive_at_ms)
    end)
    |> case do
      {frame, index} -> {index, frame}
      nil -> {length(keyframes) - 1, List.last(keyframes)}
    end
  end

  defp stopped?(frame, progress_ms) do
    progress_ms >= frame.arrive_at_ms and progress_ms < frame.depart_at_ms
  end

  defp moving_pose(route, frame, frame_index, progress_ms) do
    elapsed_seconds = progress_ms / 1_000 - frame.depart_at_ms / 1_000
    time_since_stop = frame.time_from + elapsed_seconds
    time_until_stop = frame.time_to - elapsed_seconds

    distance =
      if time_since_stop < time_until_stop do
        accelerated_distance(
          time_since_stop,
          route.accel_time,
          route.accel_rate,
          route.accel_distance,
          route.move_speed
        ) -
          frame.distance_since_stop
      else
        frame.distance_until_stop -
          accelerated_distance(
            time_until_stop,
            route.accel_time,
            route.accel_rate,
            route.accel_distance,
            route.move_speed
          )
      end

    fraction = clamp_fraction(distance / frame.next_distance_from_previous)
    position = spline_point(frame.spline, frame.spline_index, fraction)
    derivative = spline_derivative(frame.spline.points, frame.spline_index, fraction)
    orientation = normalize_orientation(:math.atan2(elem(derivative, 1), elem(derivative, 0)) + :math.pi())

    %Pose{
      map_id: frame.map_id,
      position: with_orientation(position, orientation),
      progress_ms: progress_ms,
      frame_index: frame_index,
      moving?: true,
      teleport?: frame.teleport?
    }
  end

  defp accelerated_distance(time, accel_time, accel_rate, _accel_distance, _speed) when time < accel_time do
    0.5 * accel_rate * time * time
  end

  defp accelerated_distance(time, accel_time, _accel_rate, accel_distance, speed) do
    accel_distance + (time - accel_time) * speed
  end

  defp clamp_fraction(value), do: min(max(value, 0.0), 1.0)

  defp animation_segment(frames, progress_ms) do
    following_index = Enum.find_index(frames, &(&1.time_ms >= progress_ms)) || length(frames) - 1
    following = Enum.at(frames, following_index)
    previous = Enum.at(frames, max(following_index - 1, 0))
    {max(following_index - 1, 0), previous, following}
  end

  defp animation_position(
         %AnimationFrame{time_ms: time_ms, position: position},
         %AnimationFrame{time_ms: time_ms},
         _progress
       ), do: position

  defp animation_position(previous, following, progress_ms) do
    fraction = (progress_ms - previous.time_ms) / (following.time_ms - previous.time_ms)
    lerp(previous.position, following.position, fraction)
  end

  defp rotate_animation_position({x, y, z}, {qx, qy, qz, qw}) do
    uv = cross({qx, qy, qz}, {x, y, z})
    uuv = cross({qx, qy, qz}, uv)
    add({x, y, z}, scale(add(scale(uv, qw), uuv), 2.0))
  end

  defp cross({ax, ay, az}, {bx, by, bz}) do
    {ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx}
  end

  defp add({ax, ay, az}, {bx, by, bz}), do: {ax + bx, ay + by, az + bz}
  defp scale({x, y, z}, multiplier), do: {x * multiplier, y * multiplier, z * multiplier}

  defp new_spline(points) when length(points) >= 2 do
    first = hd(points)
    second = Enum.at(points, 1)
    last = List.last(points)
    spline_points = [lerp(first, second, -1.0) | points] ++ [last]
    final_index = length(points)

    {_length, lengths} =
      Enum.reduce(1..(final_index - 1), {0.0, %{0 => 0.0, 1 => 0.0}}, fn index, {total, lengths} ->
        total = total + spline_segment_length(spline_points, index)
        {total, Map.put(lengths, index + 1, total)}
      end)

    %Spline{points: spline_points, lengths: lengths, first: 1, last: final_index}
  end

  defp spline_length(%Spline{lengths: lengths}, first, last) do
    Map.fetch!(lengths, last) - Map.fetch!(lengths, first)
  end

  defp spline_segment_length(points, index) do
    {_, length} =
      Enum.reduce(1..@spline_length_steps, {Enum.at(points, index), 0.0}, fn step, {previous, length} ->
        current = spline_point(points, index, step / @spline_length_steps)
        {current, length + Math.distance(previous, current)}
      end)

    length
  end

  defp spline_point(%Spline{points: points}, index, fraction), do: spline_point(points, index, fraction)

  defp spline_point(points, index, fraction) do
    [p0, p1, p2, p3] = Enum.slice(points, index - 1, 4)
    t2 = fraction * fraction
    t3 = t2 * fraction

    combine(
      [
        -0.5 * t3 + t2 - 0.5 * fraction,
        1.5 * t3 - 2.5 * t2 + 1.0,
        -1.5 * t3 + 2.0 * t2 + 0.5 * fraction,
        0.5 * t3 - 0.5 * t2
      ],
      [p0, p1, p2, p3]
    )
  end

  defp spline_derivative(points, index, fraction) do
    [p0, p1, p2, p3] = Enum.slice(points, index - 1, 4)
    t2 = fraction * fraction

    combine(
      [
        -1.5 * t2 + 2.0 * fraction - 0.5,
        4.5 * t2 - 5.0 * fraction,
        -4.5 * t2 + 4.0 * fraction + 0.5,
        1.5 * t2 - fraction
      ],
      [p0, p1, p2, p3]
    )
  end

  defp combine(weights, points) do
    weights
    |> Enum.zip(points)
    |> Enum.reduce({0.0, 0.0, 0.0}, fn {weight, point}, acc -> add(acc, scale(point, weight)) end)
  end

  defp lerp({x1, y1, z1}, {x2, y2, z2}, fraction) do
    {x1 + (x2 - x1) * fraction, y1 + (y2 - y1) * fraction, z1 + (z2 - z1) * fraction}
  end

  defp with_orientation({x, y, z}, orientation), do: {x, y, z, orientation}

  defp normalize_orientation(orientation) do
    orientation = :math.fmod(orientation, @two_pi)
    if orientation < 0, do: orientation + @two_pi, else: orientation
  end

  defp frame_value(frame, key), do: Map.fetch!(frame, key)
end
