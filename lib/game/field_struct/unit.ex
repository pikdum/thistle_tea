defmodule ThistleTea.Game.FieldStruct.Unit do
  alias ThistleTea.Game.Utils.UpdateObject

  use ThistleTea.Game.FieldStruct,
    charm: {0x0006, 2, :guid},
    summon: {0x0008, 2, :guid},
    charmed_by: {0x000A, 2, :guid},
    summoned_by: {0x000C, 2, :guid},
    created_by: {0x000E, 2, :guid},
    target: {0x0010, 2, :guid},
    persuaded: {0x0012, 2, :guid},
    channel_object: {0x0014, 2, :guid},
    health: {0x0016, 1, :int},
    power1: {0x0017, 1, :int},
    power2: {0x0018, 1, :int},
    power3: {0x0019, 1, :int},
    power4: {0x001A, 1, :int},
    power5: {0x001B, 1, :int},
    max_health: {0x001C, 1, :int},
    max_power1: {0x001D, 1, :int},
    max_power2: {0x001E, 1, :int},
    max_power3: {0x001F, 1, :int},
    max_power4: {0x0020, 1, :int},
    max_power5: {0x0021, 1, :int},
    level: {0x0022, 1, :int},
    faction_template: {0x0023, 1, :int},
    bytes_0:
      {0x0024, 1,
       {:fn,
        [
          :race,
          :class,
          :gender,
          :power_type
        ], &__MODULE__.bytes_0/1}},
    race: :virtual,
    class: :virtual,
    gender: :virtual,
    power_type: :virtual,
    virtual_item_slot_display: {0x0025, 3, :int},
    virtual_item_info: {0x0028, 6, :bytes},
    flags: {0x002E, 1, :int},
    aura: {0x002F, 48, :int},
    aura_flags: {0x005F, 6, :bytes},
    aura_levels: {0x0065, 12, :bytes},
    aura_applications: {0x0071, 12, :bytes},
    aura_state: {0x007D, 1, :int},
    base_attack_time: {0x007E, 2, :int},
    ranged_attack_time: {0x0080, 1, :int},
    bounding_radius: {0x0081, 1, :float},
    combat_reach: {0x0082, 1, :float},
    display_id: {0x0083, 1, :int},
    native_display_id: {0x0084, 1, :int},
    mount_display_id: {0x0085, 1, :int},
    min_damage: {0x0086, 1, :float},
    max_damage: {0x0087, 1, :float},
    min_offhand_damage: {0x0088, 1, :float},
    max_offhand_damage: {0x0089, 1, :float},
    bytes_1:
      {0x008A, 1,
       {:fn,
        [
          :stand_state,
          :pet_loyalty,
          :shapeshift_form,
          :vis_flag
        ], &__MODULE__.bytes_1/1}},
    stand_state: :virtual,
    pet_loyalty: :virtual,
    shapeshift_form: :virtual,
    vis_flag: :virtual,
    pet_number: {0x008B, 1, :int},
    pet_name_timestamp: {0x008C, 1, :int},
    pet_experience: {0x008D, 1, :int},
    pet_next_level_exp: {0x008E, 1, :int},
    dynamic_flags: {0x008F, 1, :int},
    channel_spell: {0x0090, 1, :int},
    mod_cast_speed: {0x0091, 1, :float},
    created_by_spell: {0x0092, 1, :int},
    npc_flags: {0x0093, 1, :int},
    npc_emote_state: {0x0094, 1, :int},
    training_points: {0x0095, 1, :two_short},
    strength: {0x0096, 1, :int},
    agility: {0x0097, 1, :int},
    stamina: {0x0098, 1, :int},
    intellect: {0x0099, 1, :int},
    spirit: {0x009A, 1, :int},
    normal_resistance: {0x009B, 1, :int},
    holy_resistance: {0x009C, 1, :int},
    fire_resistance: {0x009D, 1, :int},
    nature_resistance: {0x009E, 1, :int},
    frost_resistance: {0x009F, 1, :int},
    shadow_resistance: {0x00A0, 1, :int},
    arcane_resistance: {0x00A1, 1, :int},
    base_mana: {0x00A2, 1, :int},
    base_health: {0x00A3, 1, :int},
    bytes_2:
      {0x00A4, 1,
       {:fn,
        [
          :sheath_state,
          :misc_flags,
          :pet_flags
        ], &__MODULE__.bytes_2/1}},
    sheath_state: :virtual,
    misc_flags: :virtual,
    pet_flags: :virtual,
    attack_power: {0x00A5, 1, :int},
    attack_power_mods: {0x00A6, 1, :two_short},
    attack_power_multiplier: {0x00A7, 1, :float},
    ranged_attack_power: {0x00A8, 1, :int},
    ranged_attack_power_mods: {0x00A9, 1, :two_short},
    ranged_attack_power_multiplier: {0x00AA, 1, :float},
    min_ranged_damage: {0x00AB, 1, :float},
    max_ranged_damage: {0x00AC, 1, :float},
    power_cost_modifier: {0x00AD, 7, :int},
    power_cost_multiplier: {0x00B4, 7, :float}

  def bytes_0(%{race: race, class: class, gender: gender, power_type: power_type}) do
    UpdateObject.build_bytes([
      {8, race},
      {8, class},
      {8, gender},
      {8, power_type}
    ])
  end

  def bytes_1(%{
        stand_state: stand_state,
        pet_loyalty: pet_loyalty,
        shapeshift_form: shapeshift_form,
        vis_flag: vis_flag
      }) do
    UpdateObject.build_bytes([
      {8, stand_state},
      {8, pet_loyalty},
      {8, shapeshift_form},
      {8, vis_flag}
    ])
  end

  def bytes_2(%{sheath_state: sheath_state, misc_flags: misc_flags, pet_flags: pet_flags}) do
    UpdateObject.build_bytes([
      {8, sheath_state},
      {8, misc_flags},
      {8, pet_flags},
      {8, 0}
    ])
  end
end
