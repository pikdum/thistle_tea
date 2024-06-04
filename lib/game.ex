defmodule ThistleTea.Game do
  use ThousandIsland.Handler

  require Logger

  alias ThistleTea.CryptoStorage
  alias ThistleTea.SessionStorage
  alias ThistleTea.CharacterStorage

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
                # equipment
                0::little-size(760),
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

        Logger.info("packet: #{inspect(packet, limit: :infinity)}")

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

        character = %{
          guid: :binary.decode_unsigned(:crypto.strong_rand_bytes(64)),
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
          area: 85,
          map: 0,
          x: 1676.71,
          y: 1678.31,
          z: 121.67,
          orientation: 2.70526
        }

        Logger.info("[GameServer] Character: #{inspect(character, limit: :infinity)}")

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
