defmodule ThistleTea.Game.UpdateObject do
  import Binary, only: [reverse: 1]
  import Bitwise, only: [&&&: 2]

  require Logger

  @field_defs %{
    object_guid: %{
      size: 2,
      offset: 0x0
    },
    object_type: %{
      size: 1,
      offset: 0x2
    },
    object_scale_x: %{
      size: 1,
      offset: 0x4
    },
    unit_health: %{
      size: 1,
      offset: 0x16
    },
    unit_power_1: %{
      # mana
      size: 1,
      offset: 0x17
    },
    unit_power_2: %{
      # rage
      size: 1,
      offset: 0x18
    },
    unit_power_3: %{
      # focus
      size: 1,
      offset: 0x19
    },
    unit_power_4: %{
      # energy
      size: 1,
      offset: 0x1A
    },
    unit_power_5: %{
      # happiness
      size: 1,
      offset: 0x1B
    },
    unit_max_health: %{
      size: 1,
      offset: 0x1C
    },
    unit_level: %{
      size: 1,
      offset: 0x22
    },
    unit_faction_template: %{
      size: 1,
      offset: 0x23
    },
    unit_bytes_0: %{
      size: 1,
      offset: 0x24
    },
    unit_display_id: %{
      size: 1,
      offset: 0x83
    },
    unit_native_display_id: %{
      size: 1,
      offset: 0x84
    },
    player_flags: %{
      size: 1,
      offset: 0xBE
    },
    player_features: %{
      # skin, face, hair_style, hair_color
      size: 1,
      offset: 0xC1
    },
    player_xp: %{
      size: 1,
      offset: 0x2CC
    },
    player_next_level_xp: %{
      size: 1,
      offset: 0x2CD
    },
    player_rest_state_experience: %{
      size: 1,
      offset: 0x497
    }
  }

  def mask_blocks_count(fields) do
    max_offset = Enum.max(Enum.map(Map.keys(fields), &Map.get(@field_defs, &1).offset))
    trunc(:math.ceil(max_offset / 32))
  end

  def generate_mask(fields) do
    mask_count = mask_blocks_count(fields)
    mask_size = 32 * mask_count
    mask = <<0::size(mask_size)>>

    mask =
      Enum.reduce(fields, mask, fn {field, _value}, acc ->
        field_def = Map.get(@field_defs, field)
        size = field_def.size
        offset = field_def.offset

        <<left::size(mask_size - offset - size), _::size(size), right::size(offset)>> = acc

        <<left::size(mask_size - offset - size), 0xFFFFFF::size(size), right::size(offset)>>
      end)

    reverse(mask)
  end

  def generate_objects(fields) do
    fields
    |> Enum.sort(fn {f1, _}, {f2, _} ->
      Map.get(@field_defs, f1).offset < Map.get(@field_defs, f2).offset
    end)
    |> Enum.map(fn {field, value} ->
      case(field) do
        :object_guid -> <<value::little-size(64)>>
        :object_type -> <<value::little-size(32)>>
        :object_scale_x -> <<value::float-little-size(32)>>
        :unit_health -> <<value::little-size(32)>>
        :unit_power_1 -> <<value::little-size(32)>>
        :unit_power_2 -> <<value::little-size(32)>>
        :unit_power_3 -> <<value::little-size(32)>>
        :unit_power_4 -> <<value::little-size(32)>>
        :unit_power_5 -> <<value::little-size(32)>>
        :unit_max_health -> <<value::little-size(32)>>
        :unit_level -> <<value::little-size(32)>>
        :unit_faction_template -> <<value::little-size(32)>>
        :unit_bytes_0 -> value
        :unit_display_id -> <<value::little-size(32)>>
        :unit_native_display_id -> <<value::little-size(32)>>
        :player_flags -> <<value::little-size(32)>>
        :player_features -> value
        :player_xp -> <<value::little-size(32)>>
        :player_next_level_xp -> <<value::little-size(32)>>
        :player_rest_state_experience -> <<value::little-size(32)>>
        _ -> raise "Unknown field: #{field}"
      end
    end)
    |> Enum.reduce(<<>>, fn x, acc -> acc <> x end)
  end

  def encode_movement_block(m) do
    {x, y, z, orientation} = m.position

    <<m.update_flag::little-size(8)>> <>
      <<
        m.movement_flags::little-size(32),
        # unknown (timestamp?)
        0::little-size(32),
        # position
        x::little-float-size(32),
        y::little-float-size(32),
        z::little-float-size(32),
        orientation::little-float-size(32)
      >> <>
      <<m.fall_time::little-float-size(32)>> <>
      <<
        # speed block
        m.walk_speed::float-little-size(32),
        m.run_speed::float-little-size(32),
        m.run_back_speed::float-little-size(32),
        m.swim_speed::float-little-size(32),
        m.swim_back_speed::float-little-size(32),
        m.turn_rate::float-little-size(32)
      >>

    # do i need is_player?
    # or unknown hardcoded?
    # looks like yes, but why?
  end

  def decode_movement_info(m) do
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
      movement_flags: movement_flags,
      timestamp: timestamp,
      position: {x, y, z, orientation}
    }

    # on_transport
    if (movement_flags &&& 0x00000200) > 0 do
      # TODO: need to parse a packed guid
      Logger.error("[GameServer] on_transport unimplemented")
    end

    # swimming
    {movement_block, rest} =
      case (movement_flags &&& 0x00200000) > 1 do
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
      case (movement_flags &&& 0x00002000) > 0 do
        true ->
          <<z_speed::float-little-size(32), cos_angle::float-little-size(32),
            sin_angle::float-little-size(32), xy_speed::float-little-size(32),
            rest::binary>> = rest

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
      case (movement_flags &&& 0x04000000) > 0 do
        true ->
          <<spline_elevation::float-little-size(32), rest::binary>> = rest
          {Map.put(movement_block, :spline_elevation, spline_elevation), rest}

        false ->
          {movement_block, rest}
      end

    movement_block
  end
end
