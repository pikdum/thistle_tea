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
    visible_items: {0x0102, 228, :custom},
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
