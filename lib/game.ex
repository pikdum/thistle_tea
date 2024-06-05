defmodule ThistleTea.Game do
  use ThousandIsland.Handler

  require Logger

  alias ThistleTea.CryptoStorage
  alias ThistleTea.SessionStorage
  alias ThistleTea.CharacterStorage
  alias ThistleTea.Mangos
  alias ThistleTea.DBC

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

  @cmsg_logout_request 0x04B
  @smsg_logout_response 0x04C
  @smsg_logout_complete 0x04D

  @cmsg_logout_cancel 0x04E
  @smsg_logout_cancel_ack 0x04F

  def handle_packet(opcode, size, body) do
    GenServer.cast(self(), {:handle_packet, opcode, size, body})
  end

  def send_packet(opcode, payload) do
    GenServer.cast(self(), {:send_packet, opcode, payload})
  end

  @impl ThousandIsland.Handler
  def handle_connection(socket, _state) do
    Logger.info("[GameServer] SMSG_AUTH_CHALLENGE")
    seed = :crypto.strong_rand_bytes(4)

    ThousandIsland.Socket.send(
      socket,
      <<6::big-size(16), @smsg_auth_challenge::little-size(16)>> <> seed
    )

    {:continue, %{seed: seed}}
  end

  @impl ThousandIsland.Handler
  def handle_data(
        <<size::big-size(16), @cmsg_auth_session::little-size(32), body::binary-size(size - 4)>>,
        _socket,
        state
      ) do
    <<_build::little-size(32), _server_id::little-size(32), rest::binary>> = body
    {:ok, username, rest} = parse_string(rest)

    <<client_seed::little-bytes-size(4), client_proof::little-bytes-size(20), _rest::binary>> =
      rest

    session = SessionStorage.get(username)

    server_proof =
      :crypto.hash(
        :sha,
        username <> <<0::little-size(32)>> <> client_seed <> state.seed <> session
      )

    if client_proof == server_proof do
      Logger.info("[GameServer] CMSG_AUTH_SESSION: success: #{username}")
      crypt = %{key: session, send_i: 0, send_j: 0, recv_i: 0, recv_j: 0}
      {:ok, crypto_pid} = CryptoStorage.start_link(crypt)
      send_packet(@smg_auth_response, <<0x0C, 0::little-size(32), 0, 0::little-size(32)>>)
      {:continue, Map.merge(state, %{username: username, crypto_pid: crypto_pid})}
    else
      Logger.error("[GameServer] CMSG_AUTH_SESSION: error: #{username}")
      {:close, state}
    end
  end

  @impl ThousandIsland.Handler
  def handle_data(
        <<header::bytes-size(6), body::binary>>,
        _socket,
        state
      ) do
    case CryptoStorage.decrypt_header(state.crypto_pid, header) do
      <<size::big-size(16), opcode::little-size(32)>> ->
        handle_packet(opcode, size, body)

      other ->
        Logger.error("[GameServer] Error decrypting header: #{inspect(other, limit: :infinity)}")
    end

    {:continue, state}
  end

  @impl GenServer
  def handle_cast({:handle_packet, @cmsg_char_enum, _size, _body}, {socket, state}) do
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
          <<0, c.race, c.class, c.gender, c.skin, c.face, c.hairstyle, c.haircolor, c.facialhair>> <>
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

    send_packet(@smg_char_enum, packet)
    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_cast({:handle_packet, @cmsg_ping, _size, body}, {socket, state}) do
    <<sequence_id::little-size(32), latency::little-size(32)>> = body
    Logger.info("[GameServer] CMSG_PING: sequence_id: #{sequence_id}, latency: #{latency}")
    send_packet(@smg_pong, <<sequence_id::little-size(32)>>)
    {:noreply, {socket, Map.put(state, :latency, latency)}}
  end

  @impl GenServer
  def handle_cast({:handle_packet, @cmsg_char_create, _size, body}, {socket, state}) do
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
        send_packet(@smg_char_create, <<error_value>>)

      _ ->
        send_packet(@smg_char_create, <<0x2E>>)
    end

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_cast({:handle_packet, @cmsg_player_login, _size, body}, {socket, state}) do
    <<character_guid::little-size(64)>> = body
    Logger.info("[GameServer] CMSG_PLAYER_LOGIN: character_guid: #{character_guid}")

    c = CharacterStorage.get_by_guid(state.username, character_guid)

    Logger.info("[GameServer] Character: #{inspect(c)}")

    send_packet(
      @smg_login_verify_world,
      <<c.map::little-size(32), c.x::little-float-size(32), c.y::little-float-size(32),
        c.z::little-float-size(32), c.orientation::little-float-size(32)>>
    )

    send_packet(@smg_tutorial_flags, <<0::little-size(256)>>)

    chr_race = DBC.get_by(ChrRaces, id: c.race)

    unit_display_id =
      case(c.gender) do
        0 -> chr_race.male_display
        1 -> chr_race.female_display
      end

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
          1.0::float-little-size(32)
        >> <>
        <<
          # run speed
          7.0::float-little-size(32)
        >> <>
        <<
          # run back speed
          4.5::float-little-size(32)
        >> <>
        <<
          # swim speed
          0::float-little-size(32)
        >> <>
        <<
          # swim back speed
          0::float-little-size(32)
        >> <>
        <<
          3.1415::float-little-size(32)
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
        <<unit_display_id::little-size(32)>> <>
        <<unit_display_id::little-size(32)>>

    send_packet(@smg_update_object, packet)
    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_cast({:handle_packet, @cmsg_logout_request, _size, _body}, {socket, state}) do
    Logger.info("[GameServer] CMSG_LOGOUT_REQUEST")
    send_packet(@smsg_logout_response, <<0::little-size(32)>>)
    logout_timer = Process.send_after(self(), :send_logout_complete, 20_000)
    {:noreply, {socket, Map.put(state, :logout_timer, logout_timer)}}
  end

  @impl GenServer
  def handle_cast({:handle_packet, @cmsg_logout_cancel, _size, _body}, {socket, state}) do
    Logger.info("[GameServer] CMSG_LOGOUT_CANCEL")

    state =
      case Map.get(state, :logout_timer, nil) do
        nil ->
          state

        timer ->
          Process.cancel_timer(timer)
          Map.delete(state, :logout_timer)
      end

    send_packet(@smsg_logout_cancel_ack, <<>>)
    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_cast({:handle_packet, opcode, _size, _body}, {socket, state}) do
    Logger.error("[GameServer] Unhandled packet: #{inspect(opcode, base: :hex)}")
    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_cast({:send_packet, opcode, payload}, {socket, state}) do
    CryptoStorage.send_packet(
      state.crypto_pid,
      opcode,
      payload,
      socket
    )

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(:send_logout_complete, {socket, state}) do
    send_packet(@smsg_logout_complete, <<>>)
    {:noreply, {socket, state}}
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
