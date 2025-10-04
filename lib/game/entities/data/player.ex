defmodule ThistleTea.Game.Entities.Data.Player do
  alias ThistleTea.Game.Utils.NewUpdateObject

  use ThistleTea.Game.FieldStruct,
    duel_arbiter: {0x00BC, 2, :guid},
    flags: {0x00BE, 1, :int},
    guild_id: {0x00BF, 1, :int},
    guild_rank: {0x00C0, 1, :int},
    features:
      {0x00C1, 1,
       {:fn,
        [
          :skin,
          :face,
          :hair_style,
          :hair_color
        ], &__MODULE__.features/1}},
    skin: :virtual,
    face: :virtual,
    hair_style: :virtual,
    hair_color: :virtual,
    bytes_2:
      {0x00C2, 1,
       {:fn,
        [
          :facial_hair,
          :bank_bag_slots,
          :rest_state
        ], &__MODULE__.bytes_2/1}},
    facial_hair: :virtual,
    bank_bag_slots: :virtual,
    rest_state: :virtual,
    bytes_3:
      {0x00C3, 1,
       {:fn,
        [
          :gender,
          :drunk_value,
          :city_protector_title,
          :honor_rank
        ], &__MODULE__.bytes_3/1}},
    gender: :virtual,
    drunk_value: :virtual,
    city_protector_title: :virtual,
    honor_rank: :virtual,
    duel_team: {0x00C4, 1, :int},
    guild_timestamp: {0x00C5, 1, :int},
    quest_log: {0x00C6, 60, :custom},
    visible_item_1_creator: {0x0102, 2, :guid},
    visible_item_1_0: {0x0104, 8, :int},
    visible_item_1_properties: {0x010C, 1, :two_short},
    visible_item_1_pad: {0x010D, 1, :int},
    visible_item_2_creator: {0x010E, 2, :guid},
    visible_item_2_0: {0x0110, 8, :int},
    visible_item_2_properties: {0x0118, 1, :two_short},
    visible_item_2_pad: {0x0119, 1, :int},
    visible_item_3_creator: {0x011A, 2, :guid},
    visible_item_3_0: {0x011C, 8, :int},
    visible_item_3_properties: {0x0124, 1, :two_short},
    visible_item_3_pad: {0x0125, 1, :int},
    visible_item_4_creator: {0x0126, 2, :guid},
    visible_item_4_0: {0x0128, 8, :int},
    visible_item_4_properties: {0x0130, 1, :two_short},
    visible_item_4_pad: {0x0131, 1, :int},
    visible_item_5_creator: {0x0132, 2, :guid},
    visible_item_5_0: {0x0134, 8, :int},
    visible_item_5_properties: {0x013C, 1, :two_short},
    visible_item_5_pad: {0x013D, 1, :int},
    visible_item_6_creator: {0x013E, 2, :guid},
    visible_item_6_0: {0x0140, 8, :int},
    visible_item_6_properties: {0x0148, 1, :two_short},
    visible_item_6_pad: {0x0149, 1, :int},
    visible_item_7_creator: {0x014A, 2, :guid},
    visible_item_7_0: {0x014C, 8, :int},
    visible_item_7_properties: {0x0154, 1, :two_short},
    visible_item_7_pad: {0x0155, 1, :int},
    visible_item_8_creator: {0x0156, 2, :guid},
    visible_item_8_0: {0x0158, 8, :int},
    visible_item_8_properties: {0x0160, 1, :two_short},
    visible_item_8_pad: {0x0161, 1, :int},
    visible_item_9_creator: {0x0162, 2, :guid},
    visible_item_9_0: {0x0164, 8, :int},
    visible_item_9_properties: {0x016C, 1, :two_short},
    visible_item_9_pad: {0x016D, 1, :int},
    visible_item_10_creator: {0x016E, 2, :guid},
    visible_item_10_0: {0x0170, 8, :int},
    visible_item_10_properties: {0x0178, 1, :two_short},
    visible_item_10_pad: {0x0179, 1, :int},
    visible_item_11_creator: {0x017A, 2, :guid},
    visible_item_11_0: {0x017C, 8, :int},
    visible_item_11_properties: {0x0184, 1, :two_short},
    visible_item_11_pad: {0x0185, 1, :int},
    visible_item_12_creator: {0x0186, 2, :guid},
    visible_item_12_0: {0x0188, 8, :int},
    visible_item_12_properties: {0x0190, 1, :two_short},
    visible_item_12_pad: {0x0191, 1, :int},
    visible_item_13_creator: {0x0192, 2, :guid},
    visible_item_13_0: {0x0194, 8, :int},
    visible_item_13_properties: {0x019C, 1, :two_short},
    visible_item_13_pad: {0x019D, 1, :int},
    visible_item_14_creator: {0x019E, 2, :guid},
    visible_item_14_0: {0x01A0, 8, :int},
    visible_item_14_properties: {0x01A8, 1, :two_short},
    visible_item_14_pad: {0x01A9, 1, :int},
    visible_item_15_creator: {0x01AA, 2, :guid},
    visible_item_15_0: {0x01AC, 8, :int},
    visible_item_15_properties: {0x01B4, 1, :two_short},
    visible_item_15_pad: {0x01B5, 1, :int},
    visible_item_16_creator: {0x01B6, 2, :guid},
    visible_item_16_0: {0x01B8, 8, :int},
    visible_item_16_properties: {0x01C0, 1, :two_short},
    visible_item_16_pad: {0x01C1, 1, :int},
    visible_item_17_creator: {0x01C2, 2, :guid},
    visible_item_17_0: {0x01C4, 8, :int},
    visible_item_17_properties: {0x01CC, 1, :two_short},
    visible_item_17_pad: {0x01CD, 1, :int},
    visible_item_18_creator: {0x01CE, 2, :guid},
    visible_item_18_0: {0x01D0, 8, :int},
    visible_item_18_properties: {0x01D8, 1, :two_short},
    visible_item_18_pad: {0x01D9, 1, :int},
    visible_item_19_creator: {0x01DA, 2, :guid},
    visible_item_19_0: {0x01DC, 8, :int},
    visible_item_19_properties: {0x01E4, 1, :two_short},
    visible_item_19_pad: {0x01E5, 1, :int},
    field_inv: {0x01E6, 226, :custom},
    farsight: {0x02C8, 2, :guid},
    field_combo_target: {0x02CA, 2, :guid},
    xp: {0x02CC, 1, :int},
    next_level_xp: {0x02CD, 1, :int},
    skill_info: {0x02CE, 384, :custom},
    character_points1: {0x044E, 1, :int},
    character_points2: {0x044F, 1, :int},
    track_creatures: {0x0450, 1, :int},
    track_resources: {0x0451, 1, :int},
    block_percentage: {0x0452, 1, :float},
    dodge_percentage: {0x0453, 1, :float},
    parry_percentage: {0x0454, 1, :float},
    crit_percentage: {0x0455, 1, :float},
    ranged_crit_percentage: {0x0456, 1, :float},
    explored_zones: {0x0457, 64, :bytes},
    rest_state_experience: {0x0497, 1, :int},
    coinage: {0x0498, 1, :int},
    pos_stats: {0x0499, 5, :custom},
    neg_stats: {0x049E, 5, :custom},
    resistance_buff_mods_positive: {0x04A3, 7, :int},
    resistance_buff_mods_negative: {0x04AA, 7, :int},
    mod_damage_done_pos: {0x04B1, 7, :int},
    mod_damage_done_neg: {0x04B8, 7, :int},
    mod_damage_done_pct: {0x04BF, 7, :int},
    field_bytes:
      {0x04C6, 1,
       {:fn,
        [
          :field_bytes_flags,
          :combo_points,
          :action_bars,
          :highest_honor_rank
        ], &__MODULE__.field_bytes/1}},
    field_bytes_flags: :virtual,
    combo_points: :virtual,
    action_bars: :virtual,
    highest_honor_rank: :virtual,
    ammo_id: {0x04C7, 1, :int},
    self_res_spell: {0x04C8, 1, :int},
    pvp_medals: {0x04C9, 1, :int},
    buyback_prices: {0x04CA, 12, :int},
    buyback_timestamps: {0x04D6, 12, :int},
    session_kills: {0x04E2, 1, :two_short},
    yesterday_kills: {0x04E3, 1, :two_short},
    last_week_kills: {0x04E4, 1, :two_short},
    this_week_kills: {0x04E5, 1, :two_short},
    this_week_contribution: {0x04E6, 1, :int},
    lifetime_honorable_kills: {0x04E7, 1, :int},
    lifetime_dishonorable_kills: {0x04E8, 1, :int},
    yesterday_contribution: {0x04E9, 1, :int},
    last_week_contribution: {0x04EA, 1, :int},
    last_week_rank: {0x04EB, 1, :int},
    field_bytes2:
      {0x04EC, 1,
       {:fn,
        [
          :honor_rank_bar,
          :field_bytes2_flags
        ], &__MODULE__.field_bytes2/1}},
    honor_rank_bar: :virtual,
    field_bytes2_flags: :virtual,
    watched_faction_index: {0x04ED, 1, :int},
    combat_rating: {0x04EE, 20, :int}

  def features(%{skin: skin, face: face, hair_style: hair_style, hair_color: hair_color}) do
    NewUpdateObject.build_bytes([
      {8, skin},
      {8, face},
      {8, hair_style},
      {8, hair_color}
    ])
  end

  def bytes_2(%{facial_hair: facial_hair, bank_bag_slots: bank_bag_slots, rest_state: rest_state}) do
    NewUpdateObject.build_bytes([
      {8, facial_hair},
      {8, 0},
      {8, bank_bag_slots},
      {8, rest_state}
    ])
  end

  def bytes_3(%{
        gender: gender,
        drunk_value: drunk_value,
        city_protector_title: city_protector_title,
        honor_rank: honor_rank
      }) do
    gender = gender || 0
    drunk_value = drunk_value || 0
    gender_and_inebriation = Bitwise.bor(gender, Bitwise.band(drunk_value, 0xFFFE))

    NewUpdateObject.build_bytes([
      {16, gender_and_inebriation},
      {8, city_protector_title},
      {8, honor_rank}
    ])
  end

  def field_bytes(%{
        field_bytes_flags: field_bytes_flags,
        combo_points: combo_points,
        action_bars: action_bars,
        highest_honor_rank: highest_honor_rank
      }) do
    NewUpdateObject.build_bytes([
      {8, field_bytes_flags},
      {8, combo_points},
      {8, action_bars},
      {8, highest_honor_rank}
    ])
  end

  def field_bytes2(%{honor_rank_bar: honor_rank_bar, field_bytes2_flags: field_bytes2_flags}) do
    NewUpdateObject.build_bytes([{8, honor_rank_bar}, {8, field_bytes2_flags}, {16, 0}])
  end
end
