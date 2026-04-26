defmodule ThistleTea.Game.Entity.Data.Component.MovementBlock do
  import Bitwise, only: [&&&: 2, band: 2, bnot: 1, bor: 2]

  require Logger

  defstruct [
    :update_flag,
    :movement_flags,
    :timestamp,
    :position,
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

  @update_flag_transport 0x02
  @update_flag_melee_attacking 0x04
  @update_flag_high_guid 0x08
  @update_flag_all 0x10
  @update_flag_living 0x20
  @update_flag_has_position 0x40

  @movement_flag_forward 0x00000001
  @movement_flag_on_transport 0x00000200
  @movement_flag_jumping 0x00002000
  @movement_flag_swimming 0x00200000
  @movement_flag_spline_enabled 0x00400000
  @movement_flag_on_transport 0x02000000
  @movement_flag_spline_elevation 0x04000000

  @spline_flag_final_point 0x00010000
  @spline_flag_final_target 0x00020000
  @spline_flag_final_angle 0x00040000

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

    movement_block =
      Map.merge(
        acc,
        %{
          movement_flags: movement_flags,
          timestamp: timestamp,
          position: {x, y, z, orientation}
        }
      )

    # on_transport
    if (movement_flags &&& @movement_flag_on_transport) > 0 do
      Logger.error("TODO: parse packed guid for transport")
    end

    # swimming
    {movement_block, rest} =
      case (movement_flags &&& @movement_flag_swimming) > 1 do
        true ->
          <<pitch::little-float-size(32), rest::binary>> = rest
          {Map.put(movement_block, :pitch, pitch), rest}

        false ->
          {movement_block, rest}
      end

    <<fall_time::little-size(32), rest::binary>> = rest
    movement_block = Map.put(movement_block, :fall_time, fall_time)

    # jumping
    {movement_block, rest} =
      case (movement_flags &&& @movement_flag_jumping) > 0 do
        true ->
          <<z_speed::little-float-size(32), cos_angle::little-float-size(32), sin_angle::little-float-size(32),
            xy_speed::little-float-size(32), rest::binary>> = rest

          {Map.merge(movement_block, %{
             z_speed: z_speed,
             cos_angle: cos_angle,
             sin_angle: sin_angle,
             xy_speed: xy_speed
           }), rest}

        false ->
          {movement_block, rest}
      end

    # spline
    {movement_block, _rest} =
      case (movement_flags &&& @movement_flag_spline_elevation) > 0 do
        true ->
          <<spline_elevation::little-float-size(32), rest::binary>> = rest
          {Map.put(movement_block, :spline_elevation, spline_elevation), rest}

        false ->
          {movement_block, rest}
      end

    %__MODULE__{} = movement_block
  end

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

              # TODO: packed guid
              <<1, 4>> <>
                <<x::little-float-size(32), y::little-float-size(32), z::little-float-size(32),
                  orientation::little-float-size(32)>>
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
          {x, y, z, orientation} = m.position

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
        # TODO: packed guid
        <<1, 4>>
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
end
