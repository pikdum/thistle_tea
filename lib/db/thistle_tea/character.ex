defmodule ThistleTea.Character do
  use Memento.Table,
    attributes: [
      :id,
      :account_id,
      :object,
      :unit,
      :player,
      :movement_block,
      :internal
    ],
    type: :ordered_set,
    autoincrement: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.ItemTemplate
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Network.Message.CmsgCharCreate

  @item_guid_offset 0x40000000

  def build(%CmsgCharCreate{} = params, account_id) do
    info = Mangos.PlayerCreateInfo.get(params.race, params.class)
    spells = Mangos.PlayerCreateInfoSpell.get_all(params.race, params.class)
    chr_race = DBC.get_by(ChrRaces, id: params.race)

    unit_display_id =
      case(params.gender) do
        0 -> chr_race.male_display
        1 -> chr_race.female_display
      end

    %__MODULE__{
      account_id: account_id,
      object: %Object{
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
        level: 1,
        faction_template: get_alliance(params.race),
        race: params.race,
        class: params.class,
        gender: params.gender,
        power_type: get_power(params.class),
        # TODO: this is wrong
        base_attack_time: 2000,
        bounding_radius: Unit.default_bounding_radius(),
        combat_reach: Unit.default_combat_reach(),
        display_id: unit_display_id,
        native_display_id: unit_display_id,
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
        sheath_state: 0,
        # UNIT_FLAG_USE_SWIM_ANIMATION
        flags: 0x00008000
      },
      player: %Player{
        flags: 0,
        skin: params.skin_color,
        face: params.face,
        hair_style: params.hair_style,
        hair_color: params.hair_color,
        facial_hair: params.facial_hair,
        rest_state: 1,
        xp: 1,
        next_level_xp: 100,
        rest_state_experience: 100
      },
      movement_block: %MovementBlock{
        movement_flags: 0,
        position: {info.position_x, info.position_y, info.position_z, info.orientation},
        fall_time: 0.0,
        walk_speed: 1.0,
        run_speed: 7.0,
        run_back_speed: 4.5,
        swim_speed: 4.722222,
        swim_back_speed: 2.5,
        turn_rate: 3.1415,
        timestamp: 0
      },
      internal: %Internal{
        name: params.name,
        area: info.zone,
        map: info.map,
        spells: spells
      }
    }
  end

  def generate_and_assign_equipment(character) do
    equipment = CmsgCharCreate.generate_random_equipment()

    player = %{
      character.player
      | visible_item_1_0: equipment.head.entry,
        visible_item_2_0: equipment.neck.entry,
        visible_item_3_0: equipment.shoulders.entry,
        visible_item_4_0: equipment.body.entry,
        visible_item_5_0: equipment.chest.entry,
        visible_item_6_0: equipment.waist.entry,
        visible_item_7_0: equipment.legs.entry,
        visible_item_8_0: equipment.feet.entry,
        visible_item_9_0: equipment.wrists.entry,
        visible_item_10_0: equipment.hands.entry,
        visible_item_11_0: equipment.finger1.entry,
        visible_item_12_0: equipment.finger2.entry,
        visible_item_13_0: equipment.trinket1.entry,
        visible_item_14_0: equipment.trinket2.entry,
        visible_item_15_0: equipment.back.entry,
        visible_item_16_0: equipment.mainhand.entry,
        visible_item_17_0: equipment.offhand.entry,
        visible_item_19_0: equipment.tabard.entry,
        head: equipment.head.entry + @item_guid_offset,
        neck: equipment.neck.entry + @item_guid_offset,
        shoulders: equipment.shoulders.entry + @item_guid_offset,
        body: equipment.body.entry + @item_guid_offset,
        chest: equipment.chest.entry + @item_guid_offset,
        waist: equipment.waist.entry + @item_guid_offset,
        legs: equipment.legs.entry + @item_guid_offset,
        feet: equipment.feet.entry + @item_guid_offset,
        wrists: equipment.wrists.entry + @item_guid_offset,
        hands: equipment.hands.entry + @item_guid_offset,
        finger1: equipment.finger1.entry + @item_guid_offset,
        finger2: equipment.finger2.entry + @item_guid_offset,
        trinket1: equipment.trinket1.entry + @item_guid_offset,
        trinket2: equipment.trinket2.entry + @item_guid_offset,
        back: equipment.back.entry + @item_guid_offset,
        mainhand: equipment.mainhand.entry + @item_guid_offset,
        offhand: equipment.offhand.entry + @item_guid_offset,
        tabard: equipment.tabard.entry + @item_guid_offset
    }

    character = %{character | player: player}
    sync_mainhand_stats(character, equipment.mainhand)
  end

  def sync_mainhand_stats(%__MODULE__{player: %Player{visible_item_16_0: entry}} = character)
      when is_integer(entry) and entry > 0 do
    case Mangos.Repo.get(ItemTemplate, entry) do
      %ItemTemplate{} = weapon -> sync_mainhand_stats(character, weapon)
      _ -> character
    end
  end

  def sync_mainhand_stats(%__MODULE__{} = character), do: character

  def sync_mainhand_stats(%__MODULE__{unit: %Unit{} = unit} = character, %ItemTemplate{} = weapon) do
    unit =
      unit
      |> maybe_update_unit_value(:base_attack_time, weapon.delay)
      |> maybe_update_unit_value(:min_damage, weapon.dmg_min1)
      |> maybe_update_unit_value(:max_damage, weapon.dmg_max1)

    %{character | unit: unit}
  end

  def sync_mainhand_stats(%__MODULE__{} = character, _weapon), do: character

  defp maybe_update_unit_value(%Unit{} = unit, key, value) do
    case value do
      value when is_integer(value) and value > 0 -> Map.put(unit, key, value)
      value when is_float(value) and value > 0 -> Map.put(unit, key, value)
      _ -> unit
    end
  end

  def create(character) do
    with {:exists, false} <- {:exists, character_exists?(character.internal.name)},
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
  def get_alliance(race) do
    case race do
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
           Memento.Query.select(ThistleTea.Character, {:==, :internal, %{name: name}})
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

  def get_all do
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

    character = %{character | object: %{character.object | guid: character.id}}
    save(character)

    {:ok, character}
  end
end
