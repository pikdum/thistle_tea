defmodule ThistleTea.Game.Message.CmsgCharCreate do
  use ThistleTea.Game.ClientMessage, :CMSG_CHAR_CREATE

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.ItemTemplate
  alias ThistleTea.DBC
  alias ThistleTea.Game.FieldStruct.MovementBlock
  alias ThistleTea.Game.Message
  alias ThistleTea.Util

  require Logger

  defstruct [
    :name,
    :race,
    :class,
    :gender,
    :skin_color,
    :face,
    :hair_style,
    :hair_color,
    :facial_hair,
    :outfit_id
  ]

  @impl ClientMessage
  def handle(
        %__MODULE__{
          name: character_name,
          race: race,
          class: class,
          gender: gender,
          skin_color: skin,
          face: face,
          hair_style: hair_style,
          hair_color: hair_color,
          facial_hair: facial_hair,
          outfit_id: outfit_id
        },
        state
      ) do
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

    state
  end

  @impl ClientMessage
  def from_binary(payload) do
    with {:ok, name, rest} <- Util.parse_string(payload),
         <<race, class, gender, skin_color, face, hair_style, hair_color, facial_hair, outfit_id>> <- rest do
      %__MODULE__{
        name: name,
        race: race,
        class: class,
        gender: gender,
        skin_color: skin_color,
        face: face,
        hair_style: hair_style,
        hair_color: hair_color,
        facial_hair: facial_hair,
        outfit_id: outfit_id
      }
    end
  end

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
end
