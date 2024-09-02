defmodule ThistleTea.Character do
  use Memento.Table,
    attributes: [
      :id,
      :account_id,
      :name,
      :race,
      :class,
      :gender,
      :skin,
      :face,
      :hair_style,
      :hair_color,
      :facial_hair,
      :level,
      :area,
      :map,
      # TODO: is outfit_id needed?
      :outfit_id,
      :unit_display_id,
      :equipment,
      :movement,
      :spells,
      :sheath_state
    ],
    index: [:account_id, :name],
    type: :ordered_set,
    autoincrement: true

  # TODO: use high guids properly for all guid types
  @item_guid_offset 0x40000000

  def create(character) do
    with {:exists, false} <- {:exists, character_exists?(character.name)},
         {:limit, false} <- {:limit, at_character_limit?(character.account_id)},
         {:ok, character} <- create_character(character) do
      {:ok, character}
    else
      {:exists, true} -> {:error, :character_exists}
      {:limit, true} -> {:error, :character_limit}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_power(class) do
    case class do
      1 -> 1
      2 -> 0
      3 -> 0
      4 -> 3
      5 -> 0
      7 -> 0
      8 -> 0
      9 -> 0
      11 -> 0
    end
  end

  def get_update_fields(c) do
    # TODO: maybe have these part of character itself
    # TODO: add more of these to the data model
    %{
      object_guid: c.id,
      # TODO: what is 25?
      object_type: 25,
      object_scale_x: 1.0,
      unit_health: 100,
      unit_power_1: 10_000,
      unit_power_2: 100,
      unit_power_3: 100,
      unit_power_4: 100,
      unit_power_5: 100,
      unit_max_health: 100,
      unit_max_power_1: 10_000,
      unit_max_power_2: 100,
      unit_max_power_3: 100,
      unit_max_power_4: 100,
      unit_max_power_5: 100,
      unit_level: c.level,
      unit_faction_template: 1,
      unit_bytes_0: <<c.race, c.class, c.gender, get_power(c.class)>>,
      # TODO: safer way to get this, but is it even used here?
      unit_base_attack_time: c.equipment.mainhand.delay,
      unit_display_id: c.unit_display_id,
      unit_native_display_id: c.unit_display_id,
      unit_min_damage: 10,
      unit_max_damage: 50,
      unit_mod_cast_speed: 1.0,
      unit_strength: 50,
      unit_agility: 50,
      unit_stamina: 50,
      unit_intellect: 50,
      unit_spirit: 50,
      unit_base_mana: 100_000,
      unit_base_health: 100,
      unit_bytes_2: <<
        c.sheath_state,
        # unit pvp state
        0,
        # unit rename
        0,
        # ???
        0
      >>,
      player_flags: 0,
      player_features: <<c.skin, c.face, c.hair_style, c.hair_color>>,
      player_xp: 1,
      player_next_level_xp: 100,
      player_rest_state_experience: 100,
      # TODO: handle empty equipment slot
      player_visible_item_1_0: c.equipment.head.entry,
      player_visible_item_2_0: c.equipment.neck.entry,
      player_visible_item_3_0: c.equipment.shoulders.entry,
      player_visible_item_4_0: c.equipment.body.entry,
      player_visible_item_5_0: c.equipment.chest.entry,
      player_visible_item_6_0: c.equipment.waist.entry,
      player_visible_item_7_0: c.equipment.legs.entry,
      player_visible_item_8_0: c.equipment.feet.entry,
      player_visible_item_9_0: c.equipment.wrists.entry,
      player_visible_item_10_0: c.equipment.hands.entry,
      player_visible_item_11_0: c.equipment.finger1.entry,
      player_visible_item_12_0: c.equipment.finger2.entry,
      player_visible_item_13_0: c.equipment.trinket1.entry,
      player_visible_item_14_0: c.equipment.trinket2.entry,
      player_visible_item_15_0: c.equipment.back.entry,
      player_visible_item_16_0: c.equipment.mainhand.entry,
      player_visible_item_17_0: c.equipment.offhand.entry,
      # player_visible_item_18_0: c.equipment.ranged.entry,
      player_visible_item_19_0: c.equipment.tabard.entry,
      # TODO: these are supposed to be guids, not template entries
      # don't think this works anyways
      player_field_inv_head: c.equipment.head.entry + @item_guid_offset,
      player_field_inv_neck: c.equipment.neck.entry + @item_guid_offset,
      player_field_inv_shoulders: c.equipment.shoulders.entry + @item_guid_offset,
      player_field_inv_body: c.equipment.body.entry + @item_guid_offset,
      player_field_inv_chest: c.equipment.chest.entry + @item_guid_offset,
      player_field_inv_waist: c.equipment.waist.entry + @item_guid_offset,
      player_field_inv_legs: c.equipment.legs.entry + @item_guid_offset,
      player_field_inv_feet: c.equipment.feet.entry + @item_guid_offset,
      player_field_inv_wrists: c.equipment.wrists.entry + @item_guid_offset,
      player_field_inv_hands: c.equipment.hands.entry + @item_guid_offset,
      player_field_inv_finger1: c.equipment.finger1.entry + @item_guid_offset,
      player_field_inv_finger2: c.equipment.finger2.entry + @item_guid_offset,
      player_field_inv_trinket1: c.equipment.trinket1.entry + @item_guid_offset,
      player_field_inv_trinket2: c.equipment.trinket2.entry + @item_guid_offset,
      player_field_inv_back: c.equipment.back.entry + @item_guid_offset,
      player_field_inv_mainhand: c.equipment.mainhand.entry + @item_guid_offset,
      player_field_inv_offhand: c.equipment.offhand.entry + @item_guid_offset,
      # player_field_inv_ranged: c.equipment.ranged.entry + @item_guid_offset,
      player_field_inv_tabard: c.equipment.tabard.entry + @item_guid_offset
      # player_field_pack_1: c.equipment.mainhand.entry + @item_guid_offset
    }
  end

  def character_exists?(name) do
    case get_character(name) do
      {:error, _} -> false
      _ -> true
    end
  end

  def at_character_limit?(account_id) do
    case get_characters!(account_id) do
      characters when length(characters) >= 10 -> true
      _ -> false
    end
  end

  def get_character(account_id, character_id) do
    case Memento.transaction!(fn ->
           Memento.Query.select(
             ThistleTea.Character,
             [{:==, :account_id, account_id}, {:==, :id, character_id}]
           )
         end) do
      [] -> {:error, :character_not_found}
      [character] -> {:ok, character}
    end
  end

  def get_character(name) do
    case Memento.transaction!(fn ->
           Memento.Query.select(ThistleTea.Character, {:==, :name, name})
         end) do
      [] -> {:error, :character_not_found}
      [character] -> {:ok, character}
    end
  end

  def get_characters!(account_id) do
    Memento.transaction!(fn ->
      Memento.Query.select(ThistleTea.Character, {:==, :account_id, account_id})
    end)
  end

  def save(character) do
    Memento.transaction!(fn ->
      Memento.Query.write(character)
    end)
  end

  defp create_character(character) do
    character =
      Memento.transaction!(fn ->
        Memento.Query.write(character)
      end)

    {:ok, character}
  end
end
