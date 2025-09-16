defmodule ThistleTea.Game.Entities.Data.Player do
  use ThistleTea.Game.FieldStruct,
    duel_arbiter: {0x00BC, 2, :guid},
    flags: {0x00BE, 1, :int},
    guild_id: {0x00BF, 1, :int},
    guild_rank: {0x00C0, 1, :int},
    features:
      {0x00C1, 1,
       {:bytes,
        [
          skin: :tinyint,
          face: :tinyint,
          hair_style: :tinyint,
          hair_color: :tinyint
        ]}},
    bytes_2:
      {0x00C2, 1,
       {:bytes,
        [
          facial_hair: :tinyint,
          bytes_2_unk: :tinyint,
          bank_bag_slots: :smallint,
          rest_state: :tinyint
        ]}},
    bytes_3:
      {0x00C3, 1,
       {:bytes,
        [
          # vmangos Player.h
          # ;_;
          # how do i represent this
          # // uint16, 1 bit for gender, rest for drunk state
          # player->SetByteValue(UNIT_FIELD_BYTES_0, UNIT_BYTES_0_OFFSET_GENDER, gender);
          # player->SetUInt16Value(PLAYER_BYTES_3, PLAYER_BYTES_3_OFFSET_GENDER_AND_INEBRIATION, uint16(gender) | (player->GetDrunkValue() & 0xFFFE));
          gender_and_inebriation: :smallint,
          city_protector_title: :tinyint,
          honor_rank: :tinyint
        ]}},
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
       {:bytes,
        [
          # // used in (PLAYER_FIELD_BYTES, 0) byte values
          # enum PlayerFieldByteFlags
          # {
          #     PLAYER_FIELD_BYTE_TRACK_STEALTHED   = 0x02,
          #     PLAYER_FIELD_BYTE_RELEASE_TIMER     = 0x08,             // Display time till auto release spirit
          #     PLAYER_FIELD_BYTE_NO_RELEASE_WINDOW = 0x10              // Display no "release spirit" window at all
          # };
          field_bytes_flags: :tinyint,
          combo_points: :tinyint,
          action_bars: :tinyint,
          highest_honor_rank: :tinyint
        ]}},
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
       {:bytes,
        [
          honor_rank_bar: :tinyint,
          # // used in byte (PLAYER_FIELD_BYTES2,1) values
          # enum PlayerFieldByte2Flags
          # {
          #     PLAYER_FIELD_BYTE2_NONE              = 0x00,
          #     PLAYER_FIELD_BYTE2_DETECT_AMORE      = 0x01,            // SPELL_AURA_DETECT_AMORE
          #     PLAYER_FIELD_BYTE2_STEALTH           = 0x20,
          #     PLAYER_FIELD_BYTE2_INVISIBILITY_GLOW = 0x40
          # };
          field_bytes2_flags: :tinyint,
          field_bytes2_unk: :smallint
        ]}},
    watched_faction_index: {0x04ED, 1, :int},
    combat_rating: {0x04EE, 20, :int}
end
