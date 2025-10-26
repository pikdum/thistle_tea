defmodule ThistleTea.Game do
  use ThousandIsland.Handler

  use ThistleTea.Opcodes, [
    :SMSG_AUTH_CHALLENGE,
    :CMSG_AUTH_SESSION,
    :SMSG_AUTH_RESPONSE,
    :SMSG_PONG,
    :SMSG_TRANSFER_PENDING,
    :SMSG_NEW_WORLD,
    :SMSG_DESTROY_OBJECT,
    :SMSG_LOGOUT_COMPLETE,
    :CMSG_CHAR_ENUM,
    :CMSG_CHAR_CREATE,
    :CMSG_MESSAGECHAT,
    :CMSG_JOIN_CHANNEL,
    :CMSG_LEAVE_CHANNEL,
    :CMSG_TEXT_EMOTE,
    :CMSG_ATTACKSWING,
    :CMSG_ATTACKSTOP,
    :CMSG_SETSHEATHED,
    :CMSG_SET_SELECTION,
    :CMSG_GOSSIP_HELLO,
    :CMSG_GOSSIP_SELECT_OPTION,
    :CMSG_NPC_TEXT_QUERY,
    :CMSG_PLAYER_LOGIN,
    :MSG_MOVE_WORLDPORT_ACK,
    :CMSG_LOGOUT_REQUEST,
    :CMSG_LOGOUT_CANCEL,
    :MSG_MOVE_START_FORWARD,
    :MSG_MOVE_START_BACKWARD,
    :MSG_MOVE_STOP,
    :MSG_MOVE_START_STRAFE_LEFT,
    :MSG_MOVE_START_STRAFE_RIGHT,
    :MSG_MOVE_STOP_STRAFE,
    :MSG_MOVE_JUMP,
    :MSG_MOVE_START_TURN_LEFT,
    :MSG_MOVE_START_TURN_RIGHT,
    :MSG_MOVE_STOP_TURN,
    :MSG_MOVE_START_PITCH_UP,
    :MSG_MOVE_START_PITCH_DOWN,
    :MSG_MOVE_STOP_PITCH,
    :MSG_MOVE_SET_RUN_MODE,
    :MSG_MOVE_SET_WALK_MODE,
    :MSG_MOVE_FALL_LAND,
    :MSG_MOVE_START_SWIM,
    :MSG_MOVE_STOP_SWIM,
    :MSG_MOVE_SET_FACING,
    :MSG_MOVE_SET_PITCH,
    :MSG_MOVE_HEARTBEAT,
    :CMSG_MOVE_FALL_RESET,
    :CMSG_STANDSTATECHANGE,
    :CMSG_PING,
    :CMSG_NAME_QUERY,
    :CMSG_ITEM_QUERY_SINGLE,
    :CMSG_ITEM_NAME_QUERY,
    :CMSG_GAMEOBJECT_QUERY,
    :CMSG_CREATURE_QUERY,
    :CMSG_WHO,
    :CMSG_CAST_SPELL,
    :CMSG_CANCEL_CAST
  ]

  import Bitwise, only: [|||: 2]
  import ThistleTea.Game.Combat, only: [handle_attack_swing: 1]
  import ThistleTea.Game.Logout, only: [handle_logout: 1]
  import ThistleTea.Game.Spell, only: [handle_spell_complete: 1]
  import ThistleTea.Util, only: [send_packet: 2, send_update_packet: 1]

  alias ThistleTea.Game.Character
  alias ThistleTea.Game.Chat
  alias ThistleTea.Game.Combat
  alias ThistleTea.Game.Connection
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Gossip
  alias ThistleTea.Game.Handler
  alias ThistleTea.Game.Login
  alias ThistleTea.Game.Logout
  alias ThistleTea.Game.Message
  alias ThistleTea.Game.Movement
  alias ThistleTea.Game.Packet
  alias ThistleTea.Game.Ping
  alias ThistleTea.Game.Query
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Utils.UpdateObject
  alias ThousandIsland.Socket

  require Logger

  @character_opcodes [
    @cmsg_char_enum,
    @cmsg_char_create
  ]

  @chat_opcodes [
    @cmsg_messagechat,
    @cmsg_join_channel,
    @cmsg_leave_channel,
    @cmsg_text_emote
  ]

  @combat_opcodes [
    @cmsg_attackswing,
    @cmsg_attackstop,
    @cmsg_setsheathed,
    @cmsg_set_selection
  ]

  @gossip_opcodes [
    @cmsg_gossip_hello,
    @cmsg_gossip_select_option,
    @cmsg_npc_text_query
  ]

  @login_opcodes [
    @cmsg_player_login,
    @msg_move_worldport_ack
  ]

  @logout_opcodes [
    @cmsg_logout_request,
    @cmsg_logout_cancel
  ]

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

  @ping_opcodes [
    @cmsg_ping
  ]

  @query_opcodes [
    @cmsg_name_query,
    @cmsg_item_query_single,
    @cmsg_item_name_query,
    @cmsg_gameobject_query,
    @cmsg_creature_query,
    @cmsg_who
  ]

  @spell_opcodes [
    @cmsg_cast_spell,
    @cmsg_cancel_cast
  ]

  @update_flag_high_guid 0x08
  @update_flag_living 0x20
  @update_flag_has_position 0x40

  def dispatch_packet(opcode, payload, state) when opcode in @character_opcodes do
    Character.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, payload, state) when opcode in @chat_opcodes do
    Chat.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, payload, state) when opcode in @combat_opcodes do
    Combat.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, payload, state) when opcode in @gossip_opcodes do
    Gossip.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, payload, state) when opcode in @login_opcodes do
    Login.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, payload, state) when opcode in @logout_opcodes do
    Logout.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, payload, state) when opcode in @movement_opcodes do
    Movement.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, payload, state) when opcode in @ping_opcodes do
    Ping.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, payload, state) when opcode in @query_opcodes do
    Query.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, payload, state) when opcode in @spell_opcodes do
    Spell.handle_packet(opcode, payload, state)
  end

  def dispatch_packet(opcode, _payload, state) do
    Logger.error("UNIMPLEMENTED: #{ThistleTea.Opcodes.get(opcode)}")
    {:continue, state}
  end

  @impl ThousandIsland.Handler
  def handle_data(data, _socket, %{conn: %Connection{} = conn} = state) do
    conn =
      conn
      |> Connection.receive_data(data)
      |> Connection.enqueue_packets()

    state = handle_packets(%{state | conn: conn})

    Logger.info("State after handling packets: #{inspect(state)}")

    {:continue, state}
  end

  def handle_packets(%{conn: %Connection{packet_queue: []}} = state), do: state

  def handle_packets(%{conn: %Connection{packet_queue: [packet | rest]} = conn} = state) do
    dbg(conn)
    Logger.debug("Received packet: #{inspect(packet)}")

    case Packet.implemented?(packet.opcode) do
      true ->
        Logger.info("Handling packet (new): #{ThistleTea.Opcodes.get(packet.opcode)}")

        state = Packet.to_message(packet) |> Handler.handle(state) |> handle_outbox() |> dbg()

        Logger.info("Is this happening?")

        %{state | conn: %{state.conn | packet_queue: rest}}

      false ->
        Logger.info("Handling packet (legacy): #{ThistleTea.Opcodes.get(packet.opcode)}")
        {_, state} = dispatch_packet(packet.opcode, packet.payload, state)
        %{state | conn: %{state.conn | packet_queue: rest}}
    end
  end

  def handle_outbox(%{conn: %Connection{outbox: []}} = state), do: state

  def handle_outbox(%{conn: %Connection{outbox: [message | rest]} = conn} = state) do
    dbg(conn)
    Logger.info("Sending packet from outbox: #{inspect(message)}")
    packet = message |> Message.to_packet()
    send_packet(packet.opcode, packet.payload)
    %{state | conn: %{conn | outbox: rest}}
  end

  @impl GenServer
  def handle_cast({:send_packet, opcode, payload}, {socket, state}) do
    Logger.debug("Sending packet opcode=#{opcode} payload_size=#{byte_size(payload)}")
    size = byte_size(payload) + 2
    header = <<size::big-size(16), opcode::little-size(16)>>

    {:ok, conn, header} = Connection.Crypto.encrypt_header(state.conn, header)
    Socket.send(socket, header <> payload)
    {:noreply, {socket, %{state | conn: conn}}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:send_update_packet, packet}, {socket, state}) do
    send_update_packet(packet)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, {socket, state}) do
    packet =
      state.character
      |> ThistleTea.Character.get_update_fields()
      |> Map.merge(%{
        update_type: :create_object2,
        object_type: :player,
        movement_block:
          Map.put(
            state.character.movement,
            :update_flag,
            @update_flag_high_guid ||| @update_flag_living ||| @update_flag_has_position
          )
      })
      |> UpdateObject.to_packet()

    GenServer.cast(pid, {:send_update_packet, packet})
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:destroy_object, guid}, {socket, state}) do
    send_packet(@smsg_destroy_object, <<guid::little-size(64)>>)
    # TODO: remove from spawned_players/etc.?
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:start_teleport, x, y, z, map}, {socket, state}) do
    # Send player's client to loading screen to load the new map
    transfer_pending_packet = <<map::little-size(32)>>
    send_packet(@smsg_transfer_pending, transfer_pending_packet)

    # Update player's location
    area =
      case ThistleTea.Pathfinding.get_zone_and_area(map, {x, y, z}) do
        {_zone, area} -> area
        nil -> state.character.area
      end

    character = state.character

    character = %{
      character
      | area: area,
        map: map,
        movement: %{character.movement | position: {x, y, z, 0.0}}
    }

    SpatialHash.update(
      :players,
      state.guid,
      self(),
      character.map,
      x,
      y,
      z
    )

    state =
      Map.merge(state, %{
        character: character,
        ready: false
      })
      |> Map.drop([:spawned_players, :spawned_mobs, :spawned_game_objects])

    # Send player's client the new location
    orientation = 0

    new_world_packet = <<
      map::little-size(32),
      x::little-float-size(32),
      y::little-float-size(32),
      z::little-float-size(32),
      orientation::little-float-size(32)
    >>

    send_packet(@smsg_new_world, new_world_packet)

    # The client responds with a MSG_MOVE_WORLDPORT_ACK message which
    # is handled in the login handler as they share the same init process
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:logout_complete, {socket, state}) do
    send_packet(@smsg_logout_complete, <<>>)
    state = handle_logout(state)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:spell_complete, {socket, state}) do
    state = handle_spell_complete(state)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:attack_swing, {socket, state}) do
    state = handle_attack_swing(state)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:spawn_objects, {socket, %{character: c, ready: true} = state}) do
    # TODO: add telemetry for periodic tasks
    {x, y, z, _o} = c.movement.position

    old_players = Map.get(state, :spawned_players, MapSet.new())
    old_mobs = Map.get(state, :spawned_mobs, MapSet.new())
    old_game_objects = Map.get(state, :spawned_game_objects, MapSet.new())

    new_players =
      SpatialHash.query(:players, c.map, x, y, z, 250)
      |> MapSet.new(fn {guid, pid, _distance} -> {guid, pid} end)

    new_mobs =
      SpatialHash.query(:mobs, c.map, x, y, z, 250)
      |> MapSet.new(fn {guid, pid, _distance} -> {guid, pid} end)

    new_game_objects =
      SpatialHash.query(:game_objects, c.map, x, y, z, 250)
      |> MapSet.new(fn {guid, pid, _distance} -> {guid, pid} end)

    players_to_remove = MapSet.difference(old_players, new_players)
    mobs_to_remove = MapSet.difference(old_mobs, new_mobs)
    game_objects_to_remove = MapSet.difference(old_game_objects, new_game_objects)

    players_to_add = MapSet.difference(new_players, old_players)
    mobs_to_add = MapSet.difference(new_mobs, old_mobs)
    game_objects_to_add = MapSet.difference(new_game_objects, old_game_objects)

    # TODO: update a reverse mapping, so mobs know nearby players?
    for {guid, pid} <- players_to_remove do
      if pid != self() do
        send_packet(@smsg_destroy_object, <<guid::little-size(64)>>)
      end
    end

    for {guid, _pid} <- mobs_to_remove do
      send_packet(@smsg_destroy_object, <<guid::little-size(64)>>)
    end

    for {guid, _pid} <- game_objects_to_remove do
      send_packet(@smsg_destroy_object, <<guid::little-size(64)>>)
    end

    for {_guid, pid} <- players_to_add do
      if pid != self() do
        Entity.request_update_from(pid)
      end
    end

    for {_guid, pid} <- mobs_to_add do
      Entity.request_update_from(pid)
    end

    for {_guid, pid} <- game_objects_to_add do
      Entity.request_update_from(pid)
    end

    # TODO: redundant, refactor out?
    player_pids = new_players |> Enum.map(fn {_guid, pid} -> pid end)
    mob_pids = new_mobs |> Enum.map(fn {_guid, pid} -> pid end)

    state =
      Map.merge(state, %{
        spawned_players: new_players,
        spawned_mobs: new_mobs,
        spawned_game_objects: new_game_objects,
        player_pids: player_pids,
        mob_pids: mob_pids
      })

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:spawn_objects, {socket, state}) do
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_call(:get_entity, _from, state) do
    {:reply, :player, state}
  end

  @impl GenServer
  def handle_call(:get_name, _from, state) do
    {_socket, s} = state
    {:reply, s.character.name, state}
  end

  @impl ThousandIsland.Handler
  def handle_connection(socket, _) do
    conn = %Connection{}
    Socket.send(socket, <<6::big-size(16), @smsg_auth_challenge::little-size(16)>> <> conn.seed)
    {:continue, %{conn: conn}}
  end

  @impl ThousandIsland.Handler
  def handle_close(_socket, state) do
    Logger.info("CLIENT DISCONNECTED")
    handle_logout(state)
  end
end
