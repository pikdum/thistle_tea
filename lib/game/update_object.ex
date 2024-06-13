defmodule ThistleTea.Game.UpdateObject do
  import Binary, only: [reverse: 1]
  import Bitwise, only: [&&&: 2]

  import ThistleTea.Util, only: [pack_guid: 1]

  require Logger

  # @update_type_values 0
  # @update_type_movement 1
  # @update_type_create_object 2
  # @update_type_create_object2 3
  # @update_type_out_of_range_objects 4
  # @update_type_near_objects 5

  # @object_type_object 0
  # @object_type_item 1
  # @object_type_container 2
  # @object_type_unit 3
  # @object_type_player 4
  # @object_type_game_object 5
  # @object_type_dynamic_object 6
  # @object_type_corpse 7

  # @update_flag_none 0x00
  # @update_flag_self 0x01
  @update_flag_transport 0x02
  @update_flag_melee_attacking 0x04
  @update_flag_high_guid 0x08
  @update_flag_all 0x10
  @update_flag_living 0x20
  @update_flag_has_position 0x40

  # @movement_flag_none 0x00000000
  # @movement_flag_forward 0x00000001
  # @movement_flag_backward 0x00000002
  # @movement_flag_strafe_left 0x00000004
  # @movement_flag_strafe_right 0x00000008
  # @movement_flag_turn_left 0x00000010
  # @movement_flag_turn_right 0x00000020
  # @movement_flag_pitch_up 0x00000040
  # @movement_flag_pitch_down 0x00000080
  # @movement_flag_walk_mode 0x00000100
  @movement_flag_on_transport 0x00000200
  # @movement_flag_levitating 0x00000400
  # @movement_flag_fixed_z 0x00000800
  # @movement_flag_root 0x00001000
  @movement_flag_jumping 0x00002000
  # @movement_flag_falling_far 0x00004000
  @movement_flag_swimming 0x00200000
  @movement_flag_spline_enabled 0x00400000
  # @movement_flag_can_fly 0x00800000
  # @movement_flag_flying 0x01000000
  @movement_flag_on_transport 0x02000000
  @movement_flag_spline_elevation 0x04000000
  # @movement_flag_water_walking 0x10000000
  # @movement_flag_safe_fall 0x20000000
  # @movement_flag_hover 0x40000000

  # @spline_flag_none 0x00000000
  # @spline_flag_done 0x00000001
  # @spline_flag_falling 0x00000002
  # @spline_flag_run_mode 0x00000100
  # @spline_flag_flying 0x00000200
  # @spline_flag_no_spline 0x00000400
  @spline_flag_final_point 0x00010000
  @spline_flag_final_target 0x00020000
  @spline_flag_final_angle 0x00040000
  # @spline_flag_cyclic 0x00100000
  # @spline_flag_enter_cycle 0x00200000
  # @spline_flag_frozen 0x00400000

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
    unit_max_power_1: %{
      size: 1,
      offset: 0x1D
    },
    unit_max_power_2: %{
      size: 1,
      offset: 0x1E
    },
    unit_max_power_3: %{
      size: 1,
      offset: 0x1F
    },
    unit_max_power_4: %{
      size: 1,
      offset: 0x20
    },
    unit_max_power_5: %{
      size: 1,
      offset: 0x21
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
    # player_visible_item_1_creator: %{
    #   size: 2,
    #   offset: 0x102
    # },
    player_visible_item_1_0: %{
      size: 2,
      offset: 0x104
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
        :unit_max_power_1 -> <<value::little-size(32)>>
        :unit_max_power_2 -> <<value::little-size(32)>>
        :unit_max_power_3 -> <<value::little-size(32)>>
        :unit_max_power_4 -> <<value::little-size(32)>>
        :unit_max_power_5 -> <<value::little-size(32)>>
        :unit_level -> <<value::little-size(32)>>
        :unit_faction_template -> <<value::little-size(32)>>
        :unit_bytes_0 -> value
        :unit_display_id -> <<value::little-size(32)>>
        :unit_native_display_id -> <<value::little-size(32)>>
        :player_flags -> <<value::little-size(32)>>
        :player_features -> value
        :player_visible_item_1_0 -> <<value::little-size(32)>>
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
      cond do
        (m.update_flag &&& @update_flag_living) > 0 ->
          <<
            m.movement_flags::little-size(32),
            # timestamp
            0::little-size(32),
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
                m.z_speed::float-little-size(32),
                m.cos_angle::float-little-size(32),
                m.sin_angle::float-little-size(32),
                m.xy_speed::float-little-size(32)
              >>
            else
              <<>>
            end <>
            if (m.movement_flags &&& @movement_flag_spline_elevation) > 0 do
              <<m.spline_elevation::float-little-size(32)>>
            else
              <<>>
            end <>
            <<
              m.walk_speed::float-little-size(32),
              m.run_speed::float-little-size(32),
              m.run_back_speed::float-little-size(32),
              m.swim_speed::float-little-size(32),
              m.swim_back_speed::float-little-size(32),
              m.turn_rate::float-little-size(32)
            >> <>
            if (m.movement_flags &&& @movement_flag_spline_enabled) > 0 do
              <<m.spline_flags::size(32)>> <>
                cond do
                  (m.spline_flags &&& @spline_flag_final_angle) > 0 ->
                    <<m.angle::float-little-size(32)>>

                  (m.spline_flags &&& @spline_flag_final_target) > 0 ->
                    <<m.target_guid::little-size(64)>>

                  (m.spline_flags &&& @spline_flag_final_point) > 0 ->
                    {x, y, z} = m.final_point

                    <<x::little-float-size(32), y::little-float-size(32),
                      z::little-float-size(32)>>

                  true ->
                    <<>>
                end <>
                <<m.time_passed::little-size(32), m.duration::little-size(32),
                  Enum.count(m.spline_nodes) - 1::little-size(32)>> <>
                Enum.reduce(m.spline_nodes, <<>>, fn node, acc ->
                  {x, y, z} = node

                  acc <>
                    <<x::little-float-size(32), y::little-float-size(32),
                      z::little-float-size(32)>>
                end)
            else
              <<>>
            end

        (m.update_flag &&& @update_flag_has_position) > 0 ->
          <<x::little-float-size(32), y::little-float-size(32), z::little-float-size(32),
            orientation::little-float-size(32)>>
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
      case (movement_flags &&& @movement_flag_spline_elevation) > 0 do
        true ->
          <<spline_elevation::float-little-size(32), rest::binary>> = rest
          {Map.put(movement_block, :spline_elevation, spline_elevation), rest}

        false ->
          {movement_block, rest}
      end

    movement_block
  end

  def generate_packet(update_type, object_type, fields, movement) do
    packed_guid = pack_guid(Map.get(fields, :object_guid))
    movement_block = encode_movement_block(movement)
    mask_count = mask_blocks_count(fields)
    mask = generate_mask(fields)
    objects = generate_objects(fields)

    <<1::little-size(32), 0, update_type>> <>
      packed_guid <>
      <<object_type>> <>
      movement_block <>
      <<mask_count>> <>
      mask <>
      objects
  end
end
