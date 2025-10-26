defmodule ThistleTea.Game.Character do
  use ThistleTea.Opcodes, [:CMSG_CHAR_ENUM, :SMSG_CHAR_ENUM, :CMSG_CHAR_CREATE, :SMSG_CHAR_CREATE]

  import ThistleTea.Util, only: [parse_string: 1]

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.ItemTemplate
  alias ThistleTea.DBC
  alias ThistleTea.Game.FieldStruct.MovementBlock
  alias ThistleTea.Game.Message
  alias ThistleTea.Game.Message.SmsgCharEnum.Character
  alias ThistleTea.Game.Message.SmsgCharEnum.CharacterGear
  alias ThistleTea.Util

  require Logger

  def generate_random_equipment do
    %{
      head: ItemTemplate.random_by_type(1),
      neck: ItemTemplate.random_by_type(2),
      shoulders: ItemTemplate.random_by_type(3),
      body: ItemTemplate.random_by_type(4),
      chest: ItemTemplate.random_by_type(5),
      waist: ItemTemplate.random_by_type(6),
      legs: ItemTemplate.random_by_type(7),
      feet: ItemTemplate.random_by_type(8),
      wrists: ItemTemplate.random_by_type(9),
      hands: ItemTemplate.random_by_type(10),
      finger1: ItemTemplate.random_by_type(11),
      finger2: ItemTemplate.random_by_type(11),
      trinket1: ItemTemplate.random_by_type(12),
      trinket2: ItemTemplate.random_by_type(12),
      back: ItemTemplate.random_by_type(16),
      mainhand: ItemTemplate.random_by_type(13),
      offhand: ItemTemplate.random_by_type(13),
      tabard: ItemTemplate.random_by_type(19)
    }
  end

  def get_equipment(character, slot) do
    with equipment when not is_nil(equipment) <- Map.get(character, :equipment),
         item when not is_nil(item) <- Map.get(equipment, slot) do
      <<item.display_id::little-size(32), item.inventory_type>>
    else
      _ -> <<0::little-size(32), 0>>
    end
  end

  def handle_packet(@cmsg_char_enum, _body, state) do
    Logger.info("CMSG_CHAR_ENUM")

    characters = ThistleTea.Character.get_characters!(state.account.id)

    characters_structs =
      characters
      |> Enum.map(fn c ->
        {x, y, z, _o} = c.movement.position

        equipment =
          [
            :head,
            :neck,
            :shoulders,
            :body,
            :chest,
            :waist,
            :legs,
            :feet,
            :wrists,
            :hands,
            :finger1,
            :finger2,
            :trinket1,
            :trinket2,
            :back,
            :mainhand,
            :offhand,
            :ranged,
            :tabard
          ]
          |> Enum.map(fn slot ->
            with equipment when not is_nil(equipment) <- Map.get(c, :equipment),
                 item when not is_nil(item) <- Map.get(equipment, slot) do
              %CharacterGear{
                equipment_display_id: item.display_id,
                inventory_type: item.inventory_type
              }
            else
              _ ->
                %CharacterGear{
                  equipment_display_id: 0,
                  inventory_type: 0
                }
            end
          end)

        %Character{
          guid: c.id,
          name: c.name,
          race: c.race,
          class: c.class,
          gender: c.gender,
          skin: c.skin,
          face: c.face,
          hair_style: c.hair_style,
          hair_color: c.hair_color,
          facial_hair: c.facial_hair,
          level: c.level,
          area: c.area,
          map: c.map,
          position: {x, y, z},
          guild_id: 0,
          flags: 0,
          first_login: 0,
          pet_display_id: 0,
          pet_level: 0,
          pet_family: 0,
          equipment: equipment,
          first_bag_display_id: 0,
          first_bag_inventory_type: 0
        }
      end)

    Util.send_packet(%Message.SmsgCharEnum{
      amount_of_characters: Enum.count(characters_structs),
      characters: characters_structs
    })

    {:continue, state}
  end

  def handle_packet(@cmsg_char_create, body, state) do
    {:ok, character_name, rest} = parse_string(body)
    <<race, class, gender, skin, face, hair_style, hair_color, facial_hair, outfit_id>> = rest
    Logger.info("CMSG_CHAR_CREATE: #{character_name}")

    info = Mangos.PlayerCreateInfo.get(race, class)
    spells = Mangos.PlayerCreateInfoSpell.get_all(race, class)

    chr_race = DBC.get_by(ChrRaces, id: race)

    unit_display_id =
      case(gender) do
        0 -> chr_race.male_display
        1 -> chr_race.female_display
      end

    character = %ThistleTea.Character{
      account_id: state.account.id,
      name: character_name,
      race: race,
      class: class,
      gender: gender,
      skin: skin,
      face: face,
      hair_style: hair_style,
      hair_color: hair_color,
      facial_hair: facial_hair,
      outfit_id: outfit_id,
      level: 60,
      area: info.zone,
      map: info.map,
      unit_display_id: unit_display_id,
      movement: %MovementBlock{
        movement_flags: 0,
        position: {info.position_x, info.position_y, info.position_z, info.orientation},
        fall_time: 0.0,
        walk_speed: 1.0,
        # run_speed: 7.0,
        run_speed: 20.0,
        run_back_speed: 4.5,
        swim_speed: 4.722222,
        swim_back_speed: 2.5,
        turn_rate: 3.1415,
        timestamp: 0
      },
      equipment: generate_random_equipment(),
      spells: spells,
      sheath_state: 0
    }

    case ThistleTea.Character.create(character) do
      {:error, :character_exists} ->
        Util.send_packet(%Message.SmsgCharCreate{result: 0x31})

      {:error, :character_limit} ->
        Util.send_packet(%Message.SmsgCharCreate{result: 0x35})

      {:error, _} ->
        Util.send_packet(%Message.SmsgCharCreate{result: 0x30})

      {:ok, _} ->
        Util.send_packet(%Message.SmsgCharCreate{result: 0x2E})
    end

    {:continue, state}
  end
end
