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

  alias ThistleTea.Game.Entities.Data.Object
  alias ThistleTea.Game.Entities.Data.Unit
  alias ThistleTea.Game.Entities.Data.Player
  alias ThistleTea.Game.Utils.NewUpdateObject
  alias ThistleTea.Game.Utils.MovementBlock

  # TODO: use high guids properly for all guid types
  # enum HighGuid
  # {
  #     HIGHGUID_ITEM           = 0x4000,                       // blizz 4000
  #     HIGHGUID_CONTAINER      = 0x4000,                       // blizz 4000
  #     HIGHGUID_PLAYER         = 0x0000,                       // blizz 0000
  #     HIGHGUID_GAMEOBJECT     = 0xF110,                       // blizz F110
  #     HIGHGUID_TRANSPORT      = 0xF120,                       // blizz F120 (for GAMEOBJECT_TYPE_TRANSPORT)
  #     HIGHGUID_UNIT           = 0xF130,                       // blizz F130
  #     HIGHGUID_PET            = 0xF140,                       // blizz F140
  #     HIGHGUID_DYNAMICOBJECT  = 0xF100,                       // blizz F100
  #     HIGHGUID_CORPSE         = 0xF101,                       // blizz F100
  #     HIGHGUID_MO_TRANSPORT   = 0x1FC0,                       // blizz 1FC0 (for GAMEOBJECT_TYPE_MO_TRANSPORT)
  # };

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

  @doc """
  Used to set the proper faction based on the characters
  race.
  #Todo: set the faction on character creation.
  """
  def get_alliance(c) do
    case c.race do
      1 -> 1
      2 -> 2
      3 -> 1
      4 -> 1
      5 -> 2
      6 -> 2
      7 -> 1
      8 -> 2
    end
  end

  def get_update_fields(c) do
    # TODO: move up to player data model
    %NewUpdateObject{
      object: %Object{
        guid: c.id,
        scale_x: 1.0
      },
      unit: %Unit{
        health: 100,
        power1: 10_000,
        power2: 1000,
        power3: 1000,
        power4: 1000,
        power5: 1000,
        max_health: 100,
        max_power1: 10_000,
        max_power2: 1000,
        max_power3: 1000,
        max_power4: 1000,
        max_power5: 1000,
        level: c.level,
        faction_template: get_alliance(c),
        race: c.race,
        class: c.class,
        gender: c.gender,
        power_type: get_power(c.class),
        base_attack_time: c.equipment.mainhand.delay,
        display_id: c.unit_display_id,
        native_display_id: c.unit_display_id,
        min_damage: 10,
        max_damage: 50,
        mod_cast_speed: 1.0,
        strength: 50,
        agility: 50,
        stamina: 50,
        intellect: 50,
        spirit: 50,
        base_mana: 100_000,
        base_health: 100,
        sheath_state: c.sheath_state
      },
      player: %Player{
        flags: 0,
        skin: c.skin,
        face: c.face,
        hair_style: c.hair_style,
        hair_color: c.hair_color,
        rest_state: 1,
        xp: 1,
        next_level_xp: 100,
        rest_state_experience: 100,
        visible_item_1_0: c.equipment.head.entry,
        visible_item_2_0: c.equipment.neck.entry,
        visible_item_3_0: c.equipment.shoulders.entry,
        visible_item_4_0: c.equipment.body.entry,
        visible_item_5_0: c.equipment.chest.entry,
        visible_item_6_0: c.equipment.waist.entry,
        visible_item_7_0: c.equipment.legs.entry,
        visible_item_8_0: c.equipment.feet.entry,
        visible_item_9_0: c.equipment.wrists.entry,
        visible_item_10_0: c.equipment.hands.entry,
        visible_item_11_0: c.equipment.finger1.entry,
        visible_item_12_0: c.equipment.finger2.entry,
        visible_item_13_0: c.equipment.trinket1.entry,
        visible_item_14_0: c.equipment.trinket2.entry,
        visible_item_15_0: c.equipment.back.entry,
        visible_item_16_0: c.equipment.mainhand.entry,
        visible_item_17_0: c.equipment.offhand.entry,
        # visible_item_18_0: c.equipment.ranged.entry,
        visible_item_19_0: c.equipment.tabard.entry,
        head: c.equipment.head.entry + @item_guid_offset,
        neck: c.equipment.neck.entry + @item_guid_offset,
        shoulders: c.equipment.shoulders.entry + @item_guid_offset,
        body: c.equipment.body.entry + @item_guid_offset,
        chest: c.equipment.chest.entry + @item_guid_offset,
        waist: c.equipment.waist.entry + @item_guid_offset,
        legs: c.equipment.legs.entry + @item_guid_offset,
        feet: c.equipment.feet.entry + @item_guid_offset,
        wrists: c.equipment.wrists.entry + @item_guid_offset,
        hands: c.equipment.hands.entry + @item_guid_offset,
        finger1: c.equipment.finger1.entry + @item_guid_offset,
        finger2: c.equipment.finger2.entry + @item_guid_offset,
        trinket1: c.equipment.trinket1.entry + @item_guid_offset,
        trinket2: c.equipment.trinket2.entry + @item_guid_offset,
        back: c.equipment.back.entry + @item_guid_offset,
        mainhand: c.equipment.mainhand.entry + @item_guid_offset,
        offhand: c.equipment.offhand.entry + @item_guid_offset,
        # ranged: c.equipment.ranged.entry + @item_guid_offset,
        tabard: c.equipment.tabard.entry + @item_guid_offset
      },
      movement_block: %MovementBlock{} = c.movement
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

  def get_all() do
    Memento.transaction!(fn ->
      Memento.Query.all(ThistleTea.Character)
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
