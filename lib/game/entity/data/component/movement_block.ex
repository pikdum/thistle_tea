defmodule ThistleTea.Game.Entity.Data.Component.MovementBlock do
  @moduledoc """
  The movement block of an update-object packet: position, movement flags,
  speeds (real yards/sec, not DB rates), and spline state, with the binary
  encode/decode for the 1.12 wire format.
  """
  import Bitwise, only: [&&&: 2, |||: 2, band: 2, bnot: 1, bor: 2]

  alias ThistleTea.Game.Network.BinaryUtils

  defstruct [
    :update_flag,
    :movement_flags,
    :timestamp,
    :position,
    :stationary_position,
    :transport_guid,
    :transport_position,
    :pitch,
    :fall_time,
    :z_speed,
    :cos_angle,
    :sin_angle,
    :xy_speed,
    :spline_elevation,
    :walk_speed,
    :run_speed,
    :run_back_speed,
    :swim_speed,
    :swim_back_speed,
    :base_walk_speed,
    :base_run_speed,
    :base_run_back_speed,
    :base_swim_speed,
    :base_swim_back_speed,
    :turn_rate,
    :spline_flags,
    :angle,
    :target_guid,
    :final_point,
    :time_passed,
    :duration,
    :spline_nodes,
    :spline_id,
    :spline_start_position,
    :transport_progress_in_ms
  ]

  @player_speeds %{
    walk_speed: 1.0,
    run_speed: 7.0,
    run_back_speed: 4.5,
    swim_speed: 4.722222,
    swim_back_speed: 2.5
  }

  def player_speeds do
    Enum.reduce(@player_speeds, @player_speeds, fn {field, speed}, acc ->
      Map.put(acc, :"base_#{field}", speed)
    end)
  end

  def default_run_speed, do: @player_speeds.run_speed

  @update_flag_transport 0x02
  @update_flag_melee_attacking 0x04
  @update_flag_high_guid 0x08
  @update_flag_all 0x10
  @update_flag_living 0x20
  @update_flag_has_position 0x40

  @movement_flag_forward 0x00000001
  @movement_flag_backward 0x00000002
  @movement_flag_strafe_left 0x00000004
  @movement_flag_strafe_right 0x00000008
  @movement_flag_walk_mode 0x00000100
  @movement_flag_jumping 0x00002000
  @movement_flag_falling_far 0x00004000
  @movement_flag_swimming 0x00200000
  @movement_flag_spline_enabled 0x00400000
  @movement_flag_flying 0x01000000
  @movement_flag_on_transport 0x02000000
  @movement_flag_spline_elevation 0x04000000

  @movement_flag_mask_translating @movement_flag_forward |||
                                    @movement_flag_backward |||
                                    @movement_flag_strafe_left |||
                                    @movement_flag_strafe_right
  @movement_flag_mask_airborne @movement_flag_jumping ||| @movement_flag_falling_far

  @spline_flag_final_point 0x00010000
  @spline_flag_final_target 0x00020000
  @spline_flag_final_angle 0x00040000

  def swimming?(%__MODULE__{movement_flags: flags}) when is_integer(flags), do: (flags &&& @movement_flag_swimming) != 0
  def swimming?(_movement_block), do: false

  def translating?(%__MODULE__{movement_flags: flags}) when is_integer(flags) do
    (flags &&& @movement_flag_mask_translating) != 0
  end

  def translating?(_movement_block), do: false

  def clear_motion_flags(flags) when is_integer(flags) do
    motion_flags = @movement_flag_mask_translating ||| @movement_flag_spline_enabled ||| @movement_flag_flying
    band(flags, bnot(motion_flags))
  end

  def clear_motion_flags(_flags), do: 0

  def client_velocity(%__MODULE__{} = movement_block) do
    if translating?(movement_block) and not airborne?(movement_block) do
      movement_block
      |> translation_axes()
      |> velocity_from_axes(movement_block)
    else
      {0.0, 0.0, 0.0}
    end
  end

  def airborne?(%__MODULE__{movement_flags: flags}) when is_integer(flags) do
    (flags &&& @movement_flag_mask_airborne) != 0
  end

  def airborne?(_movement_block), do: false

  def on_transport?(%__MODULE__{transport_guid: guid, transport_position: position}) do
    is_integer(guid) and guid > 0 and is_tuple(position)
  end

  def on_transport?(_movement_block), do: false

  defp translation_axes(%__MODULE__{movement_flags: flags}) do
    forward = flag_axis(flags, @movement_flag_forward, @movement_flag_backward)
    strafe = flag_axis(flags, @movement_flag_strafe_left, @movement_flag_strafe_right)
    {forward, strafe}
  end

  defp flag_axis(flags, positive, negative) do
    flag_value(flags, positive) - flag_value(flags, negative)
  end

  defp flag_value(flags, flag) when (flags &&& flag) != 0, do: 1.0
  defp flag_value(_flags, _flag), do: 0.0

  defp velocity_from_axes({forward, strafe}, _movement_block) when forward == 0 and strafe == 0, do: {0.0, 0.0, 0.0}

  defp velocity_from_axes({forward, strafe}, %__MODULE__{position: {_x, _y, _z, orientation}} = movement_block)
       when is_number(orientation) do
    pitch = movement_pitch(movement_block)
    {fx, fy, fz} = forward_vector(orientation, pitch)
    {lx, ly, lz} = {-:math.sin(orientation), :math.cos(orientation), 0.0}
    {dx, dy, dz} = {forward * fx + strafe * lx, forward * fy + strafe * ly, forward * fz + strafe * lz}
    magnitude = :math.sqrt(dx * dx + dy * dy + dz * dz)
    speed = movement_speed(movement_block, forward)

    if magnitude > 0 and speed > 0 do
      {dx * speed / magnitude, dy * speed / magnitude, dz * speed / magnitude}
    else
      {0.0, 0.0, 0.0}
    end
  end

  defp velocity_from_axes(_axes, _movement_block), do: {0.0, 0.0, 0.0}

  defp movement_pitch(%__MODULE__{} = movement_block) do
    if swimming?(movement_block) and is_number(movement_block.pitch), do: movement_block.pitch, else: 0.0
  end

  defp forward_vector(orientation, pitch) do
    horizontal = :math.cos(pitch)
    {:math.cos(orientation) * horizontal, :math.sin(orientation) * horizontal, :math.sin(pitch)}
  end

  defp movement_speed(%__MODULE__{movement_flags: flags, walk_speed: speed}, _forward)
       when (flags &&& @movement_flag_walk_mode) != 0 and is_number(speed), do: speed

  defp movement_speed(%__MODULE__{} = movement_block, forward) when forward < 0, do: backward_speed(movement_block)

  defp movement_speed(%__MODULE__{} = movement_block, _forward), do: forward_speed(movement_block)

  defp backward_speed(%__MODULE__{movement_flags: flags, swim_back_speed: speed})
       when (flags &&& @movement_flag_swimming) != 0, do: speed || 0.0

  defp backward_speed(%__MODULE__{run_back_speed: speed}), do: speed || 0.0

  defp forward_speed(%__MODULE__{movement_flags: flags, swim_speed: speed})
       when (flags &&& @movement_flag_swimming) != 0, do: speed || 0.0

  defp forward_speed(%__MODULE__{run_speed: speed}), do: speed || 0.0

  def clear_transport(%__MODULE__{movement_flags: flags} = movement_block) do
    flags = if is_integer(flags), do: band(flags, bnot(@movement_flag_on_transport)), else: flags

    %{
      movement_block
      | movement_flags: flags,
        transport_guid: nil,
        transport_position: nil
    }
  end

  def position_changed?(%__MODULE__{transport_guid: guid, transport_position: previous}, %__MODULE__{
        transport_guid: guid,
        transport_position: current
      })
      when is_integer(guid) and is_tuple(previous) and is_tuple(current) do
    xyz(previous) != xyz(current)
  end

  def position_changed?(%__MODULE__{position: previous}, %__MODULE__{position: current}) do
    xyz(previous) != xyz(current)
  end

  def from_binary(m, acc \\ %__MODULE__{}) do
    <<
      # movement flags
      movement_flags::little-size(32),
      # timestamp
      timestamp::little-size(32),
      # position block
      x::little-float-size(32),
      y::little-float-size(32),
      z::little-float-size(32),
      orientation::little-float-size(32),
      rest::binary
    >> = m

    movement_block = %{
      acc
      | movement_flags: movement_flags,
        timestamp: timestamp,
        position: {x, y, z, orientation},
        transport_guid: nil,
        transport_position: nil
    }

    {movement_block, rest} =
      if (movement_flags &&& @movement_flag_on_transport) > 0 do
        <<transport_guid::little-size(64), x::little-float-size(32), y::little-float-size(32), z::little-float-size(32),
          orientation::little-float-size(32), rest::binary>> = rest

        {%{
           movement_block
           | transport_guid: transport_guid,
             transport_position: {x, y, z, orientation}
         }, rest}
      else
        {movement_block, rest}
      end

    # swimming
    {movement_block, rest} =
      case (movement_flags &&& @movement_flag_swimming) > 1 do
        true ->
          <<pitch::little-float-size(32), rest::binary>> = rest
          {%{movement_block | pitch: pitch}, rest}

        false ->
          {movement_block, rest}
      end

    <<fall_time::little-size(32), rest::binary>> = rest
    movement_block = %{movement_block | fall_time: fall_time}

    # jumping
    {movement_block, rest} =
      case (movement_flags &&& @movement_flag_jumping) > 0 do
        true ->
          <<z_speed::little-float-size(32), cos_angle::little-float-size(32), sin_angle::little-float-size(32),
            xy_speed::little-float-size(32), rest::binary>> = rest

          {%{
             movement_block
             | z_speed: z_speed,
               cos_angle: cos_angle,
               sin_angle: sin_angle,
               xy_speed: xy_speed
           }, rest}

        false ->
          {movement_block, rest}
      end

    # spline
    {movement_block, _rest} =
      case (movement_flags &&& @movement_flag_spline_elevation) > 0 do
        true ->
          <<spline_elevation::little-float-size(32), rest::binary>> = rest
          {%{movement_block | spline_elevation: spline_elevation}, rest}

        false ->
          {movement_block, rest}
      end

    %__MODULE__{} = movement_block
  end

  def refresh_timestamp(%__MODULE__{update_flag: update_flag, timestamp: timestamp} = m, now)
      when is_integer(update_flag) and is_integer(now) do
    if (update_flag &&& @update_flag_living) > 0 and timestamp in [nil, 0] do
      %{m | timestamp: now + 1000}
    else
      m
    end
  end

  def refresh_timestamp(%__MODULE__{} = m, _now), do: m

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def to_binary(%__MODULE__{} = m) do
    <<m.update_flag::little-size(8)>> <>
      cond do
        (m.update_flag &&& @update_flag_living) > 0 ->
          {x, y, z, orientation} = m.position
          movement_flags = object_update_movement_flags(m)

          <<
            movement_flags::little-size(32),
            # timestamp
            m.timestamp::little-size(32),
            # living position
            x::little-float-size(32),
            y::little-float-size(32),
            z::little-float-size(32),
            # living orientation
            orientation::little-float-size(32)
          >> <>
            if (movement_flags &&& @movement_flag_on_transport) > 0 do
              {x, y, z, orientation} = m.transport_position

              <<m.transport_guid::little-size(64), x::little-float-size(32), y::little-float-size(32),
                z::little-float-size(32), orientation::little-float-size(32)>>
            else
              <<>>
            end <>
            if (movement_flags &&& @movement_flag_swimming) > 0 do
              <<m.pitch::little-float-size(32)>>
            else
              <<>>
            end <>
            <<m.fall_time::little-size(32)>> <>
            if (movement_flags &&& @movement_flag_jumping) > 0 do
              <<
                m.z_speed::little-float-size(32),
                m.cos_angle::little-float-size(32),
                m.sin_angle::little-float-size(32),
                m.xy_speed::little-float-size(32)
              >>
            else
              <<>>
            end <>
            if (movement_flags &&& @movement_flag_spline_elevation) > 0 do
              <<m.spline_elevation::little-float-size(32)>>
            else
              <<>>
            end <>
            <<
              m.walk_speed::little-float-size(32),
              m.run_speed::little-float-size(32),
              m.run_back_speed::little-float-size(32),
              m.swim_speed::little-float-size(32),
              m.swim_back_speed::little-float-size(32),
              m.turn_rate::little-float-size(32)
            >> <>
            if (movement_flags &&& @movement_flag_spline_enabled) > 0 do
              spline_create_binary(m)
            else
              <<>>
            end

        (m.update_flag &&& @update_flag_has_position) > 0 ->
          {x, y, z, orientation} = update_position(m)

          <<x::little-float-size(32), y::little-float-size(32), z::little-float-size(32),
            orientation::little-float-size(32)>>

        true ->
          <<>>
      end <>
      if (m.update_flag &&& @update_flag_high_guid) > 0 do
        # unknown - mangos sets to 0
        <<0::little-size(32)>>
      else
        <<>>
      end <>
      if (m.update_flag &&& @update_flag_all) > 0 do
        # unknown - mangos sets to 1
        <<1::little-size(32)>>
      else
        <<>>
      end <>
      if (m.update_flag &&& @update_flag_melee_attacking) > 0 do
        BinaryUtils.pack_guid(m.target_guid || 0)
      else
        <<>>
      end <>
      if (m.update_flag &&& @update_flag_transport) > 0 do
        <<m.transport_progress_in_ms::little-size(32)>>
      else
        <<>>
      end
  end

  defp object_update_movement_flags(%__MODULE__{movement_flags: movement_flags} = m) do
    movement_flags = movement_flags || 0

    if (movement_flags &&& @movement_flag_spline_enabled) > 0 and not active_spline?(m) do
      band(movement_flags, bnot(bor(@movement_flag_spline_enabled, @movement_flag_forward)))
    else
      movement_flags
    end
  end

  defp update_position(%__MODULE__{update_flag: update_flag, stationary_position: stationary_position})
       when (update_flag &&& @update_flag_transport) > 0 and is_tuple(stationary_position) do
    stationary_position
  end

  defp update_position(%__MODULE__{position: position}), do: position

  defp spline_create_binary(%__MODULE__{} = m) do
    path = create_spline_path(m)
    time_passed = m.time_passed || 0
    duration = m.duration || 0
    spline_id = m.spline_id || 0

    <<m.spline_flags::little-size(32)>> <>
      facing_binary(m) <>
      <<time_passed::little-size(32), duration::little-size(32), spline_id::little-size(32),
        Enum.count(path)::little-size(32)>> <>
      spline_path_binary(path) <>
      vector_binary(final_destination(m))
  end

  defp active_spline?(%__MODULE__{
         spline_flags: spline_flags,
         spline_nodes: [_ | _],
         duration: duration,
         spline_id: spline_id
       })
       when is_integer(spline_flags) and is_integer(duration) and duration > 0 and is_integer(spline_id) do
    true
  end

  defp active_spline?(%__MODULE__{}), do: false

  defp spline_path_binary(path) do
    path
    |> Enum.with_index()
    |> Enum.reduce({<<>>, nil}, fn {node, index}, {acc, previous} ->
      {acc <> vector_binary(adjust_repeated_node(node, previous, index)), node}
    end)
    |> elem(0)
  end

  defp adjust_repeated_node({x, y, z}, {x, y, z}, index) do
    if rem(index, 2) == 1 do
      {x, y, z + 0.01}
    else
      {x, y, z + 0.02}
    end
  end

  defp adjust_repeated_node(node, _previous, _index), do: node

  defp facing_binary(%__MODULE__{spline_flags: spline_flags} = m) when is_integer(spline_flags) do
    cond do
      (spline_flags &&& @spline_flag_final_angle) > 0 ->
        angle = m.angle || 0.0
        <<angle::little-float-size(32)>>

      (spline_flags &&& @spline_flag_final_target) > 0 ->
        target_guid = m.target_guid || 0
        <<target_guid::little-size(64)>>

      (spline_flags &&& @spline_flag_final_point) > 0 ->
        vector_binary(m.final_point || final_destination(m))

      true ->
        <<>>
    end
  end

  defp facing_binary(%__MODULE__{}), do: <<>>

  defp create_spline_path(%__MODULE__{spline_nodes: [_ | _] = spline_nodes} = m) do
    controls = [spline_start_position(m) | spline_nodes]
    [virtual_start_position(controls) | controls] ++ [List.last(controls)]
  end

  defp create_spline_path(%__MODULE__{} = m), do: [spline_start_position(m), final_destination(m)]

  defp virtual_start_position([{x1, y1, z1}, {x2, y2, z2} | _]) do
    {2.0 * x1 - x2, 2.0 * y1 - y2, 2.0 * z1 - z2}
  end

  defp spline_start_position(%__MODULE__{spline_start_position: {x, y, z}}), do: {x, y, z}
  defp spline_start_position(%__MODULE__{position: {x, y, z, _o}}), do: {x, y, z}

  defp final_destination(%__MODULE__{spline_nodes: spline_nodes}) when is_list(spline_nodes) and spline_nodes != [] do
    List.last(spline_nodes)
  end

  defp final_destination(%__MODULE__{position: {x, y, z, _o}}), do: {x, y, z}

  defp vector_binary({x, y, z}) do
    <<x::little-float-size(32), y::little-float-size(32), z::little-float-size(32)>>
  end

  defp xyz({x, y, z, _orientation}), do: {x, y, z}
end
