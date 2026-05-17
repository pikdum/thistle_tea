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

  import Bitwise, only: [|||: 2]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.ItemTemplate
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.CmsgCharCreate
  alias ThistleTea.Game.Player.Stats

  @unit_flag_player_controlled 0x00000008
  @unit_flag_use_swim_animation 0x00008000

  def build(%CmsgCharCreate{} = params, account_id) do
    info = Mangos.PlayerCreateInfo.get(params.race, params.class)
    spells = Mangos.PlayerCreateInfoSpell.get_all(params.race, params.class)
    chr_race = DBC.get_by(ChrRaces, id: params.race)
    stats = Stats.get!(params.race, params.class, 1)

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
        health: stats.max_health,
        power1: stats.max_mana,
        power2: 0,
        power3: 0,
        power4: initial_energy(params.class),
        power5: 0,
        max_health: stats.max_health,
        max_power1: stats.max_mana,
        max_power2: max_rage(params.class),
        max_power3: 0,
        max_power4: initial_energy(params.class),
        max_power5: 0,
        level: stats.level,
        faction_template: chr_race.faction,
        race: params.race,
        class: params.class,
        gender: params.gender,
        power_type: get_power(params.class),
        base_attack_time: 2000,
        bounding_radius: Unit.default_bounding_radius(),
        combat_reach: Unit.default_combat_reach(),
        display_id: unit_display_id,
        native_display_id: unit_display_id,
        min_damage: 10,
        max_damage: 50,
        mod_cast_speed: 1.0,
        strength: stats.strength,
        agility: stats.agility,
        stamina: stats.stamina,
        intellect: stats.intellect,
        spirit: stats.spirit,
        base_mana: stats.base_mana,
        base_health: stats.base_health,
        sheath_state: 0,
        flags: @unit_flag_player_controlled ||| @unit_flag_use_swim_animation,
        auras: []
      },
      player: %Player{
        flags: 0,
        skin: params.skin_color,
        face: params.face,
        hair_style: params.hair_style,
        hair_color: params.hair_color,
        facial_hair: params.facial_hair,
        rest_state: 1,
        xp: 0,
        next_level_xp: stats.next_level_xp,
        rest_state_experience: 0
      },
      movement_block: %MovementBlock{
        movement_flags: 0,
        position: {info.position_x, info.position_y, info.position_z, info.orientation},
        fall_time: 0,
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

  def gain_xp(%__MODULE__{} = character, amount) when is_integer(amount) and amount > 0 do
    if character.unit.level >= Stats.max_level() do
      {character, []}
    else
      do_gain_xp(character, current_xp(character) + amount, [])
    end
  end

  def gain_xp(%__MODULE__{} = character, _amount), do: {character, []}

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
        head: Guid.from_low_guid(:item, equipment.head.entry),
        neck: Guid.from_low_guid(:item, equipment.neck.entry),
        shoulders: Guid.from_low_guid(:item, equipment.shoulders.entry),
        body: Guid.from_low_guid(:item, equipment.body.entry),
        chest: Guid.from_low_guid(:item, equipment.chest.entry),
        waist: Guid.from_low_guid(:item, equipment.waist.entry),
        legs: Guid.from_low_guid(:item, equipment.legs.entry),
        feet: Guid.from_low_guid(:item, equipment.feet.entry),
        wrists: Guid.from_low_guid(:item, equipment.wrists.entry),
        hands: Guid.from_low_guid(:item, equipment.hands.entry),
        finger1: Guid.from_low_guid(:item, equipment.finger1.entry),
        finger2: Guid.from_low_guid(:item, equipment.finger2.entry),
        trinket1: Guid.from_low_guid(:item, equipment.trinket1.entry),
        trinket2: Guid.from_low_guid(:item, equipment.trinket2.entry),
        back: Guid.from_low_guid(:item, equipment.back.entry),
        mainhand: Guid.from_low_guid(:item, equipment.mainhand.entry),
        offhand: Guid.from_low_guid(:item, equipment.offhand.entry),
        tabard: Guid.from_low_guid(:item, equipment.tabard.entry)
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

  defp do_gain_xp(%__MODULE__{unit: %Unit{level: level}, player: %Player{} = player} = character, xp, events) do
    next_level_xp = player.next_level_xp || Stats.next_level_xp(level)

    cond do
      next_level_xp <= 0 ->
        {%{character | player: %{player | xp: 0}}, Enum.reverse(events)}

      xp >= next_level_xp and level < Stats.max_level() ->
        old_stats = Stats.from_character(character)
        new_stats = Stats.get!(character.unit.race, character.unit.class, level + 1)

        character =
          character
          |> Stats.apply(new_stats)
          |> put_xp_after_level(xp - next_level_xp)

        event = Stats.level_delta(old_stats, new_stats)
        do_gain_xp(character, character.player.xp, [event | events])

      true ->
        {%{character | player: %{player | xp: xp}}, Enum.reverse(events)}
    end
  end

  defp put_xp_after_level(%__MODULE__{unit: %Unit{level: level}, player: %Player{} = player} = character, xp) do
    xp = if level >= Stats.max_level(), do: 0, else: xp
    %{character | player: %{player | xp: xp}}
  end

  defp current_xp(%__MODULE__{player: %Player{xp: xp}}) when is_integer(xp), do: xp
  defp current_xp(%__MODULE__{}), do: 0

  defp max_rage(1), do: 1000
  defp max_rage(_class), do: 0

  defp initial_energy(4), do: 100
  defp initial_energy(_class), do: 0

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

    character = %{character | object: %{character.object | guid: Guid.from_low_guid(:player, character.id)}}
    save(character)

    {:ok, character}
  end
end
