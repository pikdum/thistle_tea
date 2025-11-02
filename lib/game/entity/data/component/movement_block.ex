defmodule ThistleTea.Game.Entity.Data.Component.MovementBlock do
  import Bitwise, only: [&&&: 2]

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
    :transport_progress_in_ms
  ]

  @update_flag_transport 0x02
  @update_flag_melee_attacking 0x04
  @update_flag_high_guid 0x08
  @update_flag_all 0x10
  @update_flag_living 0x20
  @update_flag_has_position 0x40

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

    <<fall_time::little-float-size(32), rest::binary>> = rest
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

          <<
            m.movement_flags::little-size(32),
            # timestamp
            m.timestamp::little-size(32),
            # living position
            x::little-float-size(32),
            y::little-float-size(32),
            z::little-float-size(32),
            # living orientation
            orientation::little-float-size(32)
          >> <>
            if (m.movement_flags &&& @movement_flag_on_transport) > 0 do
              {x, y, z, orientation} = m.transport_position

              # TODO: packed guid
              <<1, 4>> <>
                <<x::little-float-size(32), y::little-float-size(32), z::little-float-size(32),
                  orientation::little-float-size(32)>>
            else
              <<>>
            end <>
            if (m.movement_flags &&& @movement_flag_swimming) > 0 do
              <<m.pitch::little-float-size(32)>>
            else
              <<>>
            end <>
            <<m.fall_time::little-float-size(32)>> <>
            if (m.movement_flags &&& @movement_flag_jumping) > 0 do
              <<
                m.z_speed::little-float-size(32),
                m.cos_angle::little-float-size(32),
                m.sin_angle::little-float-size(32),
                m.xy_speed::little-float-size(32)
              >>
            else
              <<>>
            end <>
            if (m.movement_flags &&& @movement_flag_spline_elevation) > 0 do
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
            if (m.movement_flags &&& @movement_flag_spline_enabled) > 0 do
              <<m.spline_flags::size(32)>> <>
                cond do
                  (m.spline_flags &&& @spline_flag_final_angle) > 0 ->
                    <<m.angle::little-float-size(32)>>

                  (m.spline_flags &&& @spline_flag_final_target) > 0 ->
                    <<m.target_guid::little-size(64)>>

                  (m.spline_flags &&& @spline_flag_final_point) > 0 ->
                    {x, y, z} = m.final_point

                    <<x::little-float-size(32), y::little-float-size(32), z::little-float-size(32)>>

                  true ->
                    <<>>
                end <>
                <<m.time_passed::little-size(32), m.duration::little-size(32),
                  Enum.count(m.spline_nodes) - 1::little-size(32)>> <>
                Enum.reduce(m.spline_nodes, <<>>, fn node, acc ->
                  {x, y, z} = node

                  # TODO: does this need the same logic as smsg_monster_move?
                  acc <>
                    <<x::little-float-size(32), y::little-float-size(32), z::little-float-size(32)>>
                end)
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
end
