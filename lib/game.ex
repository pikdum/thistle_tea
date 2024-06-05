defmodule ThistleTea.Game do
  use ThousandIsland.Handler

  require Logger

  alias ThistleTea.CryptoStorage
  alias ThistleTea.SessionStorage
  alias ThistleTea.CharacterStorage
  alias ThistleTea.Mangos

  import Binary, only: [split_at: 2, trim_trailing: 1]

  @smsg_auth_challenge 0x1EC

  @cmsg_auth_session 0x1ED
  @smg_auth_response 0x1EE

  @cmsg_char_enum 0x037
  @smg_char_enum 0x03B

  @cmsg_ping 0x1DC
  @smg_pong 0x1DD

  @cmsg_char_create 0x036
  @smg_char_create 0x03A

  @cmsg_player_login 0x03D
  @smg_login_verify_world 0x236
  @smg_tutorial_flags 0x0FD
  @smg_update_object 0x0A9
  # @smg_character_login_failed 0x03C

  @impl ThousandIsland.Handler
  def handle_connection(socket, _state) do
    # send SMSG_AUTH_CHALLENGE
    seed = :crypto.strong_rand_bytes(4)
    Logger.info("[GameServer] SMSG_AUTH_CHALLENGE")

    ThousandIsland.Socket.send(
      socket,
      <<6::big-size(16), @smsg_auth_challenge::little-size(16)>> <> seed
    )

    {:continue, %{seed: seed}}
  end

  @impl ThousandIsland.Handler
  def handle_data(
        <<size::big-size(16), @cmsg_auth_session::little-size(32), body::binary-size(size - 4)>>,
        socket,
        state
      ) do
    <<build::little-size(32), server_id::little-size(32), rest::binary>> = body

    {:ok, username, rest} = parse_string(rest)

    Logger.info(
      "[GameServer] CMSG_AUTH_SESSION: username: #{username}, build: #{build}, server_id: #{server_id}"
    )

    <<client_seed::little-bytes-size(4), client_proof::little-bytes-size(20), _rest::binary>> =
      rest

    session = SessionStorage.get(username)

    server_proof =
      :crypto.hash(
        :sha,
        username <> <<0::little-size(32)>> <> client_seed <> state.seed <> session
      )

    if client_proof == server_proof do
      Logger.info("[GameServer] Authentication successful: #{username}")
      crypt = %{key: session, send_i: 0, send_j: 0, recv_i: 0, recv_j: 0}
      {:ok, crypto_pid} = CryptoStorage.start_link(crypt)

      CryptoStorage.send_packet(
        crypto_pid,
        @smg_auth_response,
        <<0x0C, 0::little-size(32), 0, 0::little-size(32)>>,
        socket
      )

      {:continue, Map.merge(state, %{username: username, crypto_pid: crypto_pid})}
    else
      Logger.error("[GameServer] Authentication failed: #{username}")
      {:close, state}
    end
  end

  @impl ThousandIsland.Handler
  def handle_data(
        <<header::bytes-size(6), body::binary>>,
        socket,
        state
      ) do
    case CryptoStorage.decrypt_header(state.crypto_pid, header) do
      <<size::big-size(16), opcode::little-size(32)>> ->
        handle_packet(opcode, size, body, state, socket)

      other ->
        Logger.error("[GameServer] Error decrypting header: #{inspect(other, limit: :infinity)}")
    end

    {:continue, state}
  end

  def handle_packet(opcode, size, body, state, socket) do
    case opcode do
      @cmsg_char_enum ->
        Logger.info("[GameServer] CMSG_CHAR_ENUM")

        characters = CharacterStorage.get_characters(state.username)
        length = characters |> Enum.count()

        # TODO: use actual character equipment
        weapon = Mangos.get(ItemTemplate, 13262)
        tabard = Mangos.get(ItemTemplate, 15196)

        characters_payload =
          characters
          |> Enum.map(fn c ->
            <<c.guid::little-size(64)>> <>
              c.name <>
              <<0, c.race, c.class, c.gender, c.skin, c.face, c.hairstyle, c.haircolor,
                c.facialhair>> <>
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

        CryptoStorage.send_packet(
          state.crypto_pid,
          @smg_char_enum,
          packet,
          socket
        )

        {:continue, state}

      @cmsg_ping ->
        <<sequence_id::little-size(32), latency::little-size(32)>> = body

        Logger.info("[GameServer] CMSG_PING: sequence_id: #{sequence_id}, latency: #{latency}")

        CryptoStorage.send_packet(
          state.crypto_pid,
          @smg_pong,
          <<sequence_id::little-size(32)>>,
          socket
        )

        {:continue, Map.put(state, :latency, latency)}

      @cmsg_char_create ->
        {:ok, character_name, rest} = parse_string(body)
        <<race, class, gender, skin, face, hairstyle, haircolor, facialhair, outfit_id>> = rest
        Logger.info("[GameServer] CMSG_CHAR_CREATE: character_name: #{character_name}")

        info = Mangos.get_by(PlayerCreateInfo, race: race, class: class)

        character = %{
          guid: :binary.decode_unsigned(:crypto.strong_rand_bytes(8)),
          name: character_name,
          race: race,
          class: class,
          gender: gender,
          skin: skin,
          face: face,
          hairstyle: hairstyle,
          haircolor: haircolor,
          facialhair: facialhair,
          outfit_id: outfit_id,
          level: 1,
          area: info.zone,
          map: info.map,
          x: info.position_x,
          y: info.position_y,
          z: info.position_z,
          orientation: info.orientation
        }

        case CharacterStorage.add_character(state.username, character) do
          {:error, error_value} ->
            CryptoStorage.send_packet(
              state.crypto_pid,
              @smg_char_create,
              <<error_value>>,
              socket
            )

          _ ->
            CryptoStorage.send_packet(
              state.crypto_pid,
              @smg_char_create,
              <<0x2E>>,
              socket
            )
        end

        {:continue, state}

      @cmsg_player_login ->
        <<character_guid::little-size(64)>> = body
        Logger.info("[GameServer] CMSG_PLAYER_LOGIN: character_guid: #{character_guid}")

        c = CharacterStorage.get_by_guid(state.username, character_guid)

        Logger.info("[GameServer] Character: #{inspect(c)}")

        CryptoStorage.send_packet(
          state.crypto_pid,
          @smg_login_verify_world,
          <<c.map::little-size(32), c.x::little-float-size(32), c.y::little-float-size(32),
            c.z::little-float-size(32), c.orientation::little-float-size(32)>>,
          socket
        )

        CryptoStorage.send_packet(
          state.crypto_pid,
          @smg_tutorial_flags,
          <<0::little-size(256)>>,
          socket
        )

        packet =
          <<
            # block count (1)
            1,
            0,
            0,
            0
          >> <>
            <<
              # has transport
              0
            >> <>
            <<
              # update type = CREATE_NEW_OBJECT2
              3
            >> <>
            <<
              # packet guid, guid = 4
              1,
              4
            >> <>
            <<
              # object type = WO_PLAYER
              4
            >> <>
            <<
              # update flags 0x71
              113
            >> <>
            <<
              # movement flags
              0,
              0,
              0,
              0
            >> <>
            <<
              # timestamp
              0,
              0,
              0,
              0
            >> <>
            <<c.x::little-float-size(32)>> <>
            <<c.y::little-float-size(32)>> <>
            <<c.z::little-float-size(32)>> <>
            <<c.orientation::little-float-size(32)>> <>
            <<
              # fall time
              0,
              0,
              0,
              0
            >> <>
            <<
              # walk speed
              0,
              0,
              128,
              63
            >> <>
            <<
              # run speed
              0,
              0,
              140,
              66
            >> <>
            <<
              # run back speed
              0,
              0,
              144,
              64
            >> <>
            <<
              # swim speed
              0,
              0,
              0,
              0
            >> <>
            <<
              # swim back speed
              0,
              0,
              0,
              0
            >> <>
            <<
              # turn speed
              219,
              15,
              73,
              64
            >> <>
            <<
              # is player
              1
            >> <>
            <<
              # unknown hardcoded
              1,
              0,
              0
            >> <>
            <<
              # amount of mask blocks
              5
            >> <>
            <<
              # mask blocks
              23,
              0,
              64,
              16,
              28,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              24,
              0,
              0,
              0
            >> <>
            <<
              # object_field_guid
              4,
              0,
              0,
              0,
              0,
              0,
              0,
              0
            >> <>
            <<
              # object_field_type
              25,
              0,
              0,
              0
            >> <>
            <<
              # scale 1.0
              0,
              0,
              128,
              63
            >> <>
            <<
              # unit_field_health
              100,
              0,
              0,
              0
            >> <>
            <<
              # unit_field_max_health
              100,
              0,
              0,
              0
            >> <>
            <<c.level::little-size(32)>> <>
            <<
              # unit_field_faction_template
              1::little-size(32)
            >> <>
            <<
              c.race,
              c.class,
              c.gender,
              # power (rage)
              1
            >> <>
            <<
              # unit_field_displayd (50, human female)
              50,
              0,
              0,
              0
            >> <>
            <<
              # unit_field_nativedisplayid (50, human female)
              50,
              0,
              0,
              0
            >>

        CryptoStorage.send_packet(state.crypto_pid, @smg_update_object, packet, socket)

        {:continue, state}

      _ ->
        Logger.error("[GameServer] Unimplemented opcode: #{inspect(opcode, base: :hex)}")
        {:continue, state}
    end
  end

  def parse_string(payload, pos \\ 1)
  def parse_string(payload, _pos) when byte_size(payload) == 0, do: {:ok, payload, <<>>}

  def parse_string(payload, pos) do
    case :binary.at(payload, pos - 1) do
      0 ->
        {string, rest} = split_at(payload, pos)
        {:ok, trim_trailing(string), rest}

      _ ->
        parse_string(payload, pos + 1)
    end
  end
end
