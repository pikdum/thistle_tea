defmodule ThistleTea.Game.UpdateObject do
  import Bitwise, only: [&&&: 2]

  import ThistleTea.Util, only: [pack_guid: 1]
  import ThistleTea.Character, only: [get_update_fields: 1]

  require Logger

  @update_type_values 0
  # @update_type_movement 1
  @update_type_create_object 2
  @update_type_create_object2 3
  # @update_type_out_of_range_objects 4
  # @update_type_near_objects 5

  # @object_type_object 0
  @object_type_item 1
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

  @item_guid_offset 0x40000000

  @field_defs %{
    object_guid: %{
      size: 2,
      offset: 0x0
    },
    # TYPEMASK_OBJECT         = 0x0001,
    # TYPEMASK_ITEM           = 0x0002,
    # TYPEMASK_CONTAINER      = 0x0004,
    # TYPEMASK_UNIT           = 0x0008, // players also have it
    # TYPEMASK_PLAYER         = 0x0010,
    # TYPEMASK_GAMEOBJECT     = 0x0020,
    # TYPEMASK_DYNAMICOBJECT  = 0x0040,
    # TYPEMASK_CORPSE         = 0x0080,
    # this is not the same as @object_type_player and others
    # feel like it could be set dynamically based on which fields are used
    object_type: %{
      size: 1,
      offset: 0x2
    },
    object_entry: %{
      size: 1,
      offset: 0x3
    },
    object_scale_x: %{
      size: 1,
      offset: 0x4
    },
    item_owner: %{
      size: 2,
      offset: 0x6
    },
    item_contained: %{
      size: 2,
      offset: 0x8
    },
    item_creator: %{
      size: 2,
      offset: 0xA
    },
    item_gift_creator: %{
      size: 2,
      offset: 0xC
    },
    item_stack_count: %{
      size: 1,
      offset: 0xE
    },
    item_duration: %{
      size: 1,
      offset: 0xF
    },
    item_spell_charges: %{
      size: 5,
      offset: 0x10
    },
    item_flags: %{
      size: 1,
      offset: 0x15
    },
    item_enchantment: %{
      size: 21,
      offset: 0x16
    },
    item_property_seed: %{
      size: 1,
      offset: 0x2B
    },
    item_random_properties_id: %{
      size: 1,
      offset: 0x2C
    },
    item_item_text_id: %{
      size: 1,
      offset: 0x2D
    },
    item_durability: %{
      size: 1,
      offset: 0x2E
    },
    item_max_durability: %{
      size: 1,
      offset: 0x2F
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
    unit_flags: %{
      size: 1,
      offset: 0x2E
    },
    unit_base_attack_time: %{
      size: 2,
      offset: 0x93
    },
    unit_display_id: %{
      size: 1,
      offset: 0x83
    },
    unit_native_display_id: %{
      size: 1,
      offset: 0x84
    },
    unit_min_damage: %{
      size: 1,
      offset: 0x86
    },
    unit_max_damage: %{
      size: 1,
      offset: 0x87
    },
    unit_bytes_1: %{
      size: 1,
      offset: 0x8A
    },
    unit_mod_cast_speed: %{
      size: 1,
      offset: 0x91
    },
    unit_npc_flags: %{
      size: 1,
      offset: 0x93
    },
    unit_strength: %{
      size: 1,
      offset: 0x96
    },
    unit_agility: %{
      size: 1,
      offset: 0x97
    },
    unit_stamina: %{
      size: 1,
      offset: 0x98
    },
    unit_intellect: %{
      size: 1,
      offset: 0x99
    },
    unit_spirit: %{
      size: 1,
      offset: 0x9A
    },
    unit_base_mana: %{
      size: 1,
      offset: 0xA2
    },
    unit_base_health: %{
      size: 1,
      offset: 0xA3
    },
    unit_bytes_2: %{
      size: 1,
      offset: 0xA4
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
      size: 1,
      offset: 0x104
    },
    player_visible_item_2_0: %{
      size: 1,
      offset: 0x110
    },
    player_visible_item_3_0: %{
      size: 1,
      offset: 0x11C
    },
    player_visible_item_4_0: %{
      size: 1,
      offset: 0x128
    },
    player_visible_item_5_0: %{
      size: 1,
      offset: 0x134
    },
    player_visible_item_6_0: %{
      size: 1,
      offset: 0x140
    },
    player_visible_item_7_0: %{
      size: 1,
      offset: 0x14C
    },
    player_visible_item_8_0: %{
      size: 1,
      offset: 0x158
    },
    player_visible_item_9_0: %{
      size: 1,
      offset: 0x164
    },
    player_visible_item_10_0: %{
      size: 1,
      offset: 0x170
    },
    player_visible_item_11_0: %{
      size: 1,
      offset: 0x17C
    },
    player_visible_item_12_0: %{
      size: 1,
      offset: 0x188
    },
    player_visible_item_13_0: %{
      size: 1,
      offset: 0x194
    },
    player_visible_item_14_0: %{
      size: 1,
      offset: 0x1A0
    },
    player_visible_item_15_0: %{
      size: 1,
      offset: 0x1AC
    },
    player_visible_item_16_0: %{
      size: 1,
      offset: 0x1B8
    },
    player_visible_item_17_0: %{
      size: 1,
      offset: 0x1C4
    },
    player_visible_item_18_0: %{
      size: 1,
      offset: 0x1D0
    },
    player_visible_item_19_0: %{
      size: 1,
      offset: 0x1DC
    },
    # TODO: don't seem to be working
    # maybe i'm missing something
    player_field_inv_head: %{
      size: 2,
      offset: 0x1E6
    },
    player_field_inv_neck: %{
      size: 2,
      offset: 0x1E8
    },
    player_field_inv_shoulders: %{
      size: 2,
      offset: 0x1EA
    },
    player_field_inv_body: %{
      size: 2,
      offset: 0x1EC
    },
    player_field_inv_chest: %{
      size: 2,
      offset: 0x1EE
    },
    player_field_inv_waist: %{
      size: 2,
      offset: 0x1F0
    },
    player_field_inv_legs: %{
      size: 2,
      offset: 0x1F2
    },
    player_field_inv_feet: %{
      size: 2,
      offset: 0x1F4
    },
    player_field_inv_wrists: %{
      size: 2,
      offset: 0x1F6
    },
    player_field_inv_hands: %{
      size: 2,
      offset: 0x1F8
    },
    player_field_inv_finger1: %{
      size: 2,
      offset: 0x1FA
    },
    player_field_inv_finger2: %{
      size: 2,
      offset: 0x1FC
    },
    player_field_inv_trinket1: %{
      size: 2,
      offset: 0x1FE
    },
    player_field_inv_trinket2: %{
      size: 2,
      offset: 0x200
    },
    player_field_inv_back: %{
      size: 2,
      offset: 0x202
    },
    player_field_inv_mainhand: %{
      size: 2,
      offset: 0x204
    },
    player_field_inv_offhand: %{
      size: 2,
      offset: 0x206
    },
    player_field_inv_ranged: %{
      size: 2,
      offset: 0x208
    },
    player_field_inv_tabard: %{
      size: 2,
      offset: 0x20A
    },
    # to show where equipment should end
    player_field_pack_1: %{
      size: 2,
      offset: 0x214
    },
    player_field_bank_1: %{
      size: 2,
      offset: 0x234
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
    },
    game_object_display_id: %{
      size: 1,
      offset: 0x008
    },
    game_object_flags: %{
      size: 1,
      offset: 0x009
    },
    game_object_rotation0: %{
      size: 1,
      offset: 0x00A
    },
    game_object_rotation1: %{
      size: 1,
      offset: 0x00B
    },
    game_object_rotation2: %{
      size: 1,
      offset: 0x00C
    },
    game_object_rotation3: %{
      size: 1,
      offset: 0x00D
    },
    game_object_state: %{
      size: 1,
      offset: 0x00E
    },
    game_object_pos_x: %{
      size: 1,
      offset: 0x00F
    },
    game_object_pos_y: %{
      size: 1,
      offset: 0x010
    },
    game_object_pos_z: %{
      size: 1,
      offset: 0x011
    },
    game_object_facing: %{
      size: 1,
      offset: 0x012
    },
    game_object_faction: %{
      size: 1,
      offset: 0x014
    },
    game_object_type_id: %{
      size: 1,
      offset: 0x015
    },
    game_object_animprogress: %{
      size: 1,
      offset: 0x018
    }
  }

  def mask_blocks_count(fields) do
    max_offset = Enum.max(Enum.map(Map.keys(fields), &Map.get(@field_defs, &1).offset))
    max(trunc(:math.ceil(max_offset / 32)), 1)
  end

  def generate_mask(fields) do
    mask_count = mask_blocks_count(fields)
    mask_size = 32 * mask_count
    mask = Bitmap.new(mask_size)

    mask =
      Enum.reduce(fields, mask, fn {field, _value}, acc ->
        field_def = Map.get(@field_defs, field)
        size = field_def.size
        start = field_def.offset
        stop = start + size - 1

        # from start to stop, set bits to 1
        Enum.reduce(start..stop, acc, fn i, acc ->
          Bitmap.set(acc, i)
        end)
      end)

    <<mask.data::little-size(mask_size)>>
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
        :object_entry -> <<value::little-size(32)>>
        :object_scale_x -> <<value::little-float-size(32)>>
        :item_owner -> <<value::little-size(64)>>
        :item_contained -> <<value::little-size(64)>>
        :item_creator -> <<value::little-size(64)>>
        :item_gift_creator -> <<value::little-size(64)>>
        :item_stack_count -> <<value::little-size(32)>>
        :item_duration -> <<value::little-size(32)>>
        :item_durability -> <<value::little-size(32)>>
        :item_max_durability -> <<value::little-size(32)>>
        :item_flags -> <<value::little-size(32)>>
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
        :unit_flags -> <<value::little-size(32)>>
        :unit_base_attack_time -> <<value::little-size(64)>>
        :unit_display_id -> <<value::little-size(32)>>
        :unit_native_display_id -> <<value::little-size(32)>>
        :unit_min_damage -> <<value::little-float-size(32)>>
        :unit_max_damage -> <<value::little-float-size(32)>>
        :unit_bytes_1 -> value
        :unit_mod_cast_speed -> <<value::little-float-size(32)>>
        :unit_npc_flags -> <<value::little-size(32)>>
        :unit_strength -> <<value::little-size(32)>>
        :unit_agility -> <<value::little-size(32)>>
        :unit_stamina -> <<value::little-size(32)>>
        :unit_intellect -> <<value::little-size(32)>>
        :unit_spirit -> <<value::little-size(32)>>
        :unit_base_mana -> <<value::little-size(32)>>
        :unit_base_health -> <<value::little-size(32)>>
        :unit_bytes_2 -> value
        :player_flags -> <<value::little-size(32)>>
        :player_features -> value
        :player_visible_item_1_0 -> <<value::little-size(32)>>
        :player_visible_item_2_0 -> <<value::little-size(32)>>
        :player_visible_item_3_0 -> <<value::little-size(32)>>
        :player_visible_item_4_0 -> <<value::little-size(32)>>
        :player_visible_item_5_0 -> <<value::little-size(32)>>
        :player_visible_item_6_0 -> <<value::little-size(32)>>
        :player_visible_item_7_0 -> <<value::little-size(32)>>
        :player_visible_item_8_0 -> <<value::little-size(32)>>
        :player_visible_item_9_0 -> <<value::little-size(32)>>
        :player_visible_item_10_0 -> <<value::little-size(32)>>
        :player_visible_item_11_0 -> <<value::little-size(32)>>
        :player_visible_item_12_0 -> <<value::little-size(32)>>
        :player_visible_item_13_0 -> <<value::little-size(32)>>
        :player_visible_item_14_0 -> <<value::little-size(32)>>
        :player_visible_item_15_0 -> <<value::little-size(32)>>
        :player_visible_item_16_0 -> <<value::little-size(32)>>
        :player_visible_item_17_0 -> <<value::little-size(32)>>
        :player_visible_item_18_0 -> <<value::little-size(32)>>
        :player_visible_item_19_0 -> <<value::little-size(32)>>
        :player_field_inv_head -> <<value::little-size(64)>>
        :player_field_inv_neck -> <<value::little-size(64)>>
        :player_field_inv_shoulders -> <<value::little-size(64)>>
        :player_field_inv_body -> <<value::little-size(64)>>
        :player_field_inv_chest -> <<value::little-size(64)>>
        :player_field_inv_waist -> <<value::little-size(64)>>
        :player_field_inv_legs -> <<value::little-size(64)>>
        :player_field_inv_feet -> <<value::little-size(64)>>
        :player_field_inv_wrists -> <<value::little-size(64)>>
        :player_field_inv_hands -> <<value::little-size(64)>>
        :player_field_inv_finger1 -> <<value::little-size(64)>>
        :player_field_inv_finger2 -> <<value::little-size(64)>>
        :player_field_inv_trinket1 -> <<value::little-size(64)>>
        :player_field_inv_trinket2 -> <<value::little-size(64)>>
        :player_field_inv_back -> <<value::little-size(64)>>
        :player_field_inv_mainhand -> <<value::little-size(64)>>
        :player_field_inv_offhand -> <<value::little-size(64)>>
        :player_field_inv_ranged -> <<value::little-size(64)>>
        :player_field_inv_tabard -> <<value::little-size(64)>>
        :player_field_pack_1 -> <<value::little-size(64)>>
        :player_xp -> <<value::little-size(32)>>
        :player_next_level_xp -> <<value::little-size(32)>>
        :player_rest_state_experience -> <<value::little-size(32)>>
        :game_object_display_id -> <<value::little-size(32)>>
        :game_object_flags -> <<value::little-size(32)>>
        :game_object_rotation0 -> <<value::little-float-size(32)>>
        :game_object_rotation1 -> <<value::little-float-size(32)>>
        :game_object_rotation2 -> <<value::little-float-size(32)>>
        :game_object_rotation3 -> <<value::little-float-size(32)>>
        :game_object_state -> <<value::little-size(32)>>
        :game_object_pos_x -> <<value::little-float-size(32)>>
        :game_object_pos_y -> <<value::little-float-size(32)>>
        :game_object_pos_z -> <<value::little-float-size(32)>>
        :game_object_facing -> <<value::little-float-size(32)>>
        :game_object_faction -> <<value::little-size(32)>>
        :game_object_type_id -> <<value::little-size(32)>>
        :game_object_animprogress -> <<value::little-size(32)>>
        _ -> raise "Unknown field: #{field}"
      end
    end)
    |> Enum.reduce(<<>>, fn x, acc -> acc <> x end)
  end

  def encode_movement_block(m) do
    <<m.update_flag::little-size(8)>> <>
      cond do
        (m.update_flag &&& @update_flag_living) > 0 ->
          <<
            m.movement_flags::little-size(32),
            # timestamp
            m.timestamp::little-size(32),
            # living position
            m.x::little-float-size(32),
            m.y::little-float-size(32),
            m.z::little-float-size(32),
            # living orientation
            m.orientation::little-float-size(32)
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
          <<m.x::little-float-size(32), m.y::little-float-size(32), m.z::little-float-size(32),
            m.orientation::little-float-size(32)>>

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
      x: x,
      y: y,
      z: z,
      orientation: orientation
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
          <<z_speed::little-float-size(32), cos_angle::little-float-size(32),
            sin_angle::little-float-size(32), xy_speed::little-float-size(32),
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
          <<spline_elevation::little-float-size(32), rest::binary>> = rest
          {Map.put(movement_block, :spline_elevation, spline_elevation), rest}

        false ->
          {movement_block, rest}
      end

    movement_block
  end

  def generate_packet(@update_type_values, fields) do
    packed_guid = pack_guid(Map.get(fields, :object_guid))
    mask_count = mask_blocks_count(fields)
    mask = generate_mask(fields)
    objects = generate_objects(fields)

    <<1::little-size(32), 0, @update_type_values>> <>
      packed_guid <> <<mask_count>> <> mask <> objects
  end

  def generate_packet(update_type, object_type, fields, movement)
      when update_type in [@update_type_create_object, @update_type_create_object2] do
    packed_guid = pack_guid(Map.get(fields, :object_guid))
    mask_count = mask_blocks_count(fields)
    mask = generate_mask(fields)
    objects = generate_objects(fields)
    movement_block = encode_movement_block(movement)

    <<1::little-size(32), 0, update_type>> <>
      packed_guid <>
      <<object_type>> <>
      movement_block <>
      <<mask_count>> <>
      mask <>
      objects
  end

  def build_update_packet(
        character,
        update_type,
        object_type,
        update_flag
      )
      when update_type in [@update_type_create_object, @update_type_create_object2] do
    fields = get_update_fields(character)

    generate_packet(
      update_type,
      object_type,
      fields,
      Map.put(
        character.movement,
        :update_flag,
        update_flag
      )
    )
  end

  # TODO: i really need to clean this up
  def get_item_packets(items) do
    items
    |> Enum.map(fn {_, item} ->
      fields = %{
        object_guid: item.entry + @item_guid_offset,
        # object + item
        object_type: 3,
        object_entry: item.entry,
        item_flags: item.flags
      }

      mb = %{
        update_flag: 0
      }

      generate_packet(@update_type_create_object2, @object_type_item, fields, mb)
    end)
  end
end
