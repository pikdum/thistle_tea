defmodule ThistleTea.Game.Character do
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

  defmacro __using__(_) do
    quote do
      alias ThistleTea.Mangos
      alias ThistleTea.DBC

      import ThistleTea.Util, only: [parse_string: 1]
      import ThistleTea.Game.Character, only: [generate_random_equipment: 0, get_equipment: 2]

      @cmsg_char_enum 0x037
      @smsg_char_enum 0x03B

      @cmsg_char_create 0x036
      @smsg_char_create 0x03A

      @impl GenServer
      def handle_cast({:handle_packet, @cmsg_char_enum, _size, _body}, {socket, state}) do
        Logger.info("CMSG_CHAR_ENUM")

        characters = ThistleTea.Character.get_characters!(state.account.id)
        length = characters |> Enum.count()

        characters_payload =
          characters
          |> Enum.map(fn c ->
            <<c.id::little-size(64)>> <>
              c.name <>
              <<0, c.race, c.class, c.gender, c.skin, c.face, c.hair_style, c.hair_color,
                c.facial_hair>> <>
              <<
                c.level,
                c.area::little-size(32),
                c.map::little-size(32),
                c.movement.x::float-size(32),
                c.movement.y::float-size(32),
                c.movement.z::float-size(32)
              >> <>
              <<
                # guild_id
                0::little-size(32),
                # flags
                0::little-size(32),
                # first_login
                0,
                # pet_display_id
                0::little-size(32),
                # pet_level
                0::little-size(32),
                # pet_family
                0::little-size(32)
              >> <>
              get_equipment(c, :head) <>
              get_equipment(c, :neck) <>
              get_equipment(c, :shoulders) <>
              get_equipment(c, :body) <>
              get_equipment(c, :chest) <>
              get_equipment(c, :waist) <>
              get_equipment(c, :legs) <>
              get_equipment(c, :feet) <>
              get_equipment(c, :wrists) <>
              get_equipment(c, :hands) <>
              get_equipment(c, :finger1) <>
              get_equipment(c, :finger2) <>
              get_equipment(c, :trinket1) <>
              get_equipment(c, :trinket2) <>
              get_equipment(c, :back) <>
              get_equipment(c, :mainhand) <>
              get_equipment(c, :offhand) <>
              get_equipment(c, :ranged) <>
              get_equipment(c, :tabard) <>
              <<
                # first_bag_display_id
                0::little-size(32),
                # first_bag_inventory_type
                0
              >>
          end)

        packet =
          case length do
            0 -> <<0>>
            _ -> <<length>> <> Enum.join(characters_payload)
          end

        send_packet(@smsg_char_enum, packet)
        {:noreply, {socket, state}, socket.read_timeout}
      end

      @impl GenServer
      def handle_cast({:handle_packet, @cmsg_char_create, _size, body}, {socket, state}) do
        {:ok, character_name, rest} = parse_string(body)
        <<race, class, gender, skin, face, hair_style, hair_color, facial_hair, outfit_id>> = rest
        Logger.info("CMSG_CHAR_CREATE: #{character_name}")

        info = Mangos.get_by(PlayerCreateInfo, race: race, class: class)

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
          level: 1,
          area: info.zone,
          map: info.map,
          unit_display_id: unit_display_id,
          movement: %{
            movement_flags: 0,
            x: info.position_x,
            y: info.position_y,
            z: info.position_z,
            orientation: info.orientation,
            fall_time: 0.0,
            walk_speed: 1.0,
            # run_speed: 7.0,
            run_speed: 20.0,
            run_back_speed: 4.5,
            swim_speed: 0.0,
            swim_back_speed: 0.0,
            turn_rate: 3.1415,
            timestamp: 0
          },
          equipment: generate_random_equipment()
        }

        case ThistleTea.Character.create(character) do
          {:error, :character_exists} ->
            send_packet(@smsg_char_create, <<0x31>>)

          {:error, :character_limit} ->
            send_packet(@smsg_char_create, <<0x35>>)

          {:error, _} ->
            send_packet(@smsg_char_create, <<0x30>>)

          {:ok, _} ->
            send_packet(@smsg_char_create, <<0x2E>>)
        end

        {:noreply, {socket, state}, socket.read_timeout}
      end
    end
  end
end
