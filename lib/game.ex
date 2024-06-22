defmodule ThistleTea.Game do
  use ThousandIsland.Handler

  import Bitwise, only: [|||: 2]
  import ThistleTea.Game.Logout, only: [handle_logout: 1]
  import ThistleTea.Game.UpdateObject, only: [build_update_packet: 4]
  import ThistleTea.Util, only: [send_packet: 2, send_update_packet: 1, parse_string: 1]

  alias ThistleTea.CryptoStorage

  require Logger

  @smsg_auth_challenge 0x1EC
  @cmsg_auth_session 0x1ED
  @smsg_auth_response 0x1EE
  @smsg_pong 0x1DD

  @smsg_logout_complete 0x04D

  @cmsg_char_enum 0x037
  @cmsg_char_create 0x036

  @character_opcodes [
    @cmsg_char_enum,
    @cmsg_char_create
  ]

  @cmsg_messagechat 0x095
  @cmsg_join_channel 0x097

  @chat_opcodes [
    @cmsg_messagechat,
    @cmsg_join_channel
  ]

  @cmsg_player_login 0x03D

  @login_opcodes [
    @cmsg_player_login
  ]

  @cmsg_logout_request 0x04B
  @cmsg_logout_cancel 0x04E

  @logout_opcodes [
    @cmsg_logout_request,
    @cmsg_logout_cancel
  ]

  @msg_move_start_forward 0x0B5
  @msg_move_start_backward 0x0B6
  @msg_move_stop 0x0B7
  @msg_move_start_strafe_left 0x0B8
  @msg_move_start_strafe_right 0x0B9
  @msg_move_stop_strafe 0x0BA
  @msg_move_jump 0x0BB
  @msg_move_start_turn_left 0x0BC
  @msg_move_start_turn_right 0x0BD
  @msg_move_stop_turn 0x0BE
  @msg_move_start_pitch_up 0x0BF
  @msg_move_start_pitch_down 0x0C0
  @msg_move_stop_pitch 0x0C1
  @msg_move_set_run_mode 0x0C2
  @msg_move_set_walk_mode 0x0C3
  @msg_move_fall_land 0x0C9
  @msg_move_start_swim 0x0CA
  @msg_move_stop_swim 0x0CB
  @msg_move_set_facing 0x0DA
  @msg_move_set_pitch 0x0DB
  @msg_move_heartbeat 0x0EE
  @cmsg_move_fall_reset 0x2CA
  @cmsg_standstatechange 0x101

  @movement_opcodes [
    @msg_move_start_forward,
    @msg_move_start_backward,
    @msg_move_stop,
    @msg_move_start_strafe_left,
    @msg_move_start_strafe_right,
    @msg_move_stop_strafe,
    @msg_move_jump,
    @msg_move_start_turn_left,
    @msg_move_start_turn_right,
    @msg_move_stop_turn,
    @msg_move_start_pitch_up,
    @msg_move_start_pitch_down,
    @msg_move_stop_pitch,
    @msg_move_set_run_mode,
    @msg_move_set_walk_mode,
    @msg_move_fall_land,
    @msg_move_start_swim,
    @msg_move_stop_swim,
    @msg_move_set_facing,
    @msg_move_set_pitch,
    @msg_move_heartbeat,
    @cmsg_move_fall_reset,
    @cmsg_standstatechange
  ]

  @cmsg_ping 0x1DC

  @ping_opcodes [
    @cmsg_ping
  ]

  @cmsg_name_query 0x050
  @cmsg_item_query_single 0x056
  @cmsg_creature_query 0x060

  @query_opcodes [
    @cmsg_name_query,
    @cmsg_item_query_single,
    @cmsg_creature_query
  ]

  @update_type_create_object2 3
  @object_type_player 4
  @update_flag_high_guid 0x08
  @update_flag_living 0x20
  @update_flag_has_position 0x40

  def dispatch_packet(opcode, payload, state) when opcode in @character_opcodes do
    ThistleTea.Game.Character.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, payload, state) when opcode in @chat_opcodes do
    ThistleTea.Game.Chat.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, payload, state) when opcode in @login_opcodes do
    ThistleTea.Game.Login.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, payload, state) when opcode in @logout_opcodes do
    ThistleTea.Game.Logout.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, payload, state) when opcode in @movement_opcodes do
    ThistleTea.Game.Movement.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, payload, state) when opcode in @ping_opcodes do
    ThistleTea.Game.Ping.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, payload, state) when opcode in @query_opcodes do
    ThistleTea.Game.Query.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, _payload, state) do
    Logger.error("UNIMPLEMENTED: #{inspect(opcode, base: :hex)}")
    {:continue, state}
  end

  @impl ThousandIsland.Handler
  def handle_data(
        <<size::big-size(16), @cmsg_auth_session::little-size(32), body::binary-size(size - 4),
          additional_data::binary>>,
        socket,
        state
      ) do
    if byte_size(additional_data) > 0, do: handle_data(additional_data, socket, state)
    <<_build::little-size(32), _server_id::little-size(32), rest::binary>> = body
    {:ok, username, rest} = parse_string(rest)
    Logger.metadata(username: username)
    Logger.info("CMSG_AUTH_SESSION")

    <<client_seed::little-bytes-size(4), client_proof::little-bytes-size(20), _rest::binary>> =
      rest

    [{^username, session}] = :ets.lookup(:session, username)

    server_proof =
      :crypto.hash(
        :sha,
        username <> <<0::little-size(32)>> <> client_seed <> state.seed <> session
      )

    if client_proof == server_proof do
      Logger.info("AUTH SUCCESS")
      crypt = %{key: session, send_i: 0, send_j: 0, recv_i: 0, recv_j: 0}
      {:ok, crypto_pid} = CryptoStorage.start_link(crypt)
      {:ok, account} = ThistleTea.Account.get_user(username)
      send_packet(@smsg_auth_response, <<0x0C, 0::little-size(32), 0, 0::little-size(32)>>)

      {:continue, Map.merge(state, %{crypto_pid: crypto_pid, account: account})}
    else
      Logger.error("AUTH FAILURE")
      {:close, state}
    end
  end

  @impl ThousandIsland.Handler
  def handle_data(
        <<size::big-size(16), @cmsg_ping::little-size(32), body::binary-size(size - 4),
          additional_data::binary>>,
        socket,
        state
      ) do
    if byte_size(additional_data) > 0, do: handle_data(additional_data, socket, state)
    <<sequence_id::little-size(32), latency::little-size(32)>> = body

    Logger.info("CMSG_PING latency=#{latency}")

    ThousandIsland.Socket.send(
      socket,
      <<6::big-size(16), @smsg_pong::little-size(16), sequence_id::little-size(32)>>
    )

    {:continue, Map.put(state, :latency, latency)}
  end

  @impl ThousandIsland.Handler
  def handle_data(
        data,
        _socket,
        state
      ) do
    state = Map.put(state, :packet_stream, Map.get(state, :packet_stream, <<>>) <> data)
    handle_packet(state)
  end

  def handle_packet(%{packet_stream: <<header::bytes-size(6), rest::binary>>} = state) do
    with {:ok, decrypted_header} <-
           CryptoStorage.decrypt_header(state.crypto_pid, header, byte_size(rest)) do
      <<size::big-size(16), opcode::little-size(32)>> = decrypted_header
      <<payload::binary-size(size - 4), rest::binary>> = rest
      state = Map.put(state, :packet_stream, rest)
      {action, state} = dispatch_packet(opcode, payload, state)

      # try to handle the next packet
      if byte_size(rest) >= 6 do
        handle_packet(state)
      else
        {action, state}
      end
    else
      {:error, _} -> {:continue, state}
    end
  end

  # accumulate packet_stream until enough data
  def handle_packet(state), do: state

  @impl GenServer
  def handle_cast({:send_packet, opcode, payload}, {socket, state}) do
    {:ok, header} = CryptoStorage.encrypt_header(state.crypto_pid, opcode, payload)
    ThousandIsland.Socket.send(socket, header <> payload)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_call(
        {:build_update_packet, update_type, object_type, update_flag},
        _from,
        {socket, state}
      ) do
    packet = build_update_packet(state.character, update_type, object_type, update_flag)

    {:reply, packet, {socket, state}}
  end

  @impl GenServer
  def handle_call(:spawn_packet, _from, {socket, state}) do
    packet =
      build_update_packet(
        state.character,
        @update_type_create_object2,
        @object_type_player,
        @update_flag_high_guid ||| @update_flag_living ||| @update_flag_has_position
      )

    {:reply, packet, {socket, state}}
  end

  @impl GenServer
  def handle_info({:send_packet, opcode, payload}, {socket, state}) do
    send_packet(opcode, payload)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info({:send_update_packet, packet}, {socket, state}) do
    send_update_packet(packet)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:logout_complete, {socket, state}) do
    send_packet(@smsg_logout_complete, <<>>)
    handle_logout(state)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl ThousandIsland.Handler
  def handle_connection(socket, _state) do
    Logger.info("SMSG_AUTH_CHALLENGE")
    seed = :crypto.strong_rand_bytes(4)

    ThousandIsland.Socket.send(
      socket,
      <<6::big-size(16), @smsg_auth_challenge::little-size(16)>> <> seed
    )

    spawned_guids = :ets.new(:spawned_guids, [:set])

    {:continue, %{seed: seed, spawned_guids: spawned_guids}}
  end

  @impl ThousandIsland.Handler
  def handle_close(_socket, state) do
    Logger.info("CLIENT DISCONNECTED")
    handle_logout(state)
  end
end
