defmodule ThistleTea.Game.Character do
  defmacro __using__(_) do
    quote do
      alias ThistleTea.Mangos
      import ThistleTea.Util, only: [parse_string: 1]

      @cmsg_char_enum 0x037
      @smsg_char_enum 0x03B

      @cmsg_char_create 0x036
      @smsg_char_create 0x03A

      @impl GenServer
      def handle_cast({:handle_packet, @cmsg_char_enum, _size, _body}, {socket, state}) do
        Logger.info("CMSG_CHAR_ENUM")

        characters = ThistleTea.Character.get_characters!(state.account.id)
        length = characters |> Enum.count()

        # TODO: use actual character equipment
        weapon = Mangos.get(ItemTemplate, 13262)
        tabard = Mangos.get(ItemTemplate, 15196)

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
                c.x::float-size(32),
                c.y::float-size(32),
                c.z::float-size(32)
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
              <<
                # head
                0::little-size(32),
                0
              >> <>
              <<
                # neck
                0::little-size(32),
                0
              >> <>
              <<
                # shoulders
                0::little-size(32),
                0
              >> <>
              <<
                # body
                0::little-size(32),
                0
              >> <>
              <<
                # chest
                0::little-size(32),
                0
              >> <>
              <<
                # waist
                0::little-size(32),
                0
              >> <>
              <<
                # legs
                0::little-size(32),
                0
              >> <>
              <<
                # feet
                0::little-size(32),
                0
              >> <>
              <<
                # wrists
                0::little-size(32),
                0
              >> <>
              <<
                # hands
                0::little-size(32),
                0
              >> <>
              <<
                # finger1
                0::little-size(32),
                0
              >> <>
              <<
                # finger2
                0::little-size(32),
                0
              >> <>
              <<
                # trinket1
                0::little-size(32),
                0
              >> <>
              <<
                # trinket2
                0::little-size(32),
                0
              >> <>
              <<
                # back
                0::little-size(32),
                0
              >> <>
              <<
                # mainhand
                weapon.display_id::little-size(32),
                0
              >> <>
              <<
                # offhand
                weapon.display_id::little-size(32),
                0
              >> <>
              <<
                # ranged
                0::little-size(32),
                0
              >> <>
              <<
                # tabard
                tabard.display_id::little-size(32),
                0
              >> <>
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
          x: info.position_x,
          y: info.position_y,
          z: info.position_z,
          orientation: info.orientation
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
