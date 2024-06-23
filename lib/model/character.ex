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
      :movement
    ],
    index: [:account_id, :name],
    type: :ordered_set,
    autoincrement: true

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

  def get_update_fields(c) do
    # TODO: maybe have these part of character itself
    # TODO: add more of these to the data model
    %{
      object_guid: c.id,
      # TODO: what is 25?
      object_type: 25,
      object_scale_x: 1.0,
      unit_health: 100,
      unit_power_1: 100,
      unit_power_2: 100,
      unit_power_3: 100,
      unit_power_4: 100,
      unit_power_5: 100,
      unit_max_health: 100,
      unit_max_power_1: 100,
      unit_max_power_2: 100,
      unit_max_power_3: 100,
      unit_max_power_4: 100,
      unit_max_power_5: 100,
      unit_level: c.level,
      unit_faction_template: 1,
      unit_bytes_0: <<c.race, c.class, c.gender, 1>>,
      unit_base_attack_time: 2000,
      unit_display_id: c.unit_display_id,
      unit_native_display_id: c.unit_display_id,
      unit_strength: 50,
      unit_agility: 50,
      unit_stamina: 50,
      unit_intellect: 50,
      unit_spirit: 50,
      unit_base_mana: 100,
      unit_base_health: 100,
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
      # player_visible_item_17_0: c.equipment.offhand.entry,
      # player_visible_item_18_0: c.equipment.ranged.entry,
      player_visible_item_19_0: c.equipment.tabard.entry
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
