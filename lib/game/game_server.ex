defmodule ThistleTea.Game do
  use ThousandIsland.Handler
  use ThistleTea.Opcodes, [:SMSG_AUTH_CHALLENGE]

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Connection
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Message
  alias ThistleTea.Game.Packet
  alias ThistleTea.Game.Utils.UpdateObject
  alias ThistleTea.Util
  alias ThousandIsland.Socket

  require Logger

  @update_flag_high_guid 0x08
  @update_flag_living 0x20
  @update_flag_has_position 0x40

  @impl ThousandIsland.Handler
  def handle_data(data, _socket, %{conn: %Connection{} = conn} = state) do
    conn =
      conn
      |> Connection.receive_data(data)
      |> Connection.enqueue_packets()

    state = handle_packets(%{state | conn: conn})

    {:continue, state}
  end

  def handle_packets(%{conn: %Connection{packet_queue: []}} = state), do: state

  def handle_packets(%{conn: %Connection{packet_queue: [packet | rest]}} = state) do
    message_name = ThistleTea.Opcodes.get(packet.opcode)

    case Packet.implemented?(packet.opcode) do
      true ->
        Logger.debug("Received: #{message_name}")

        state =
          :telemetry.span([:thistle_tea, :handle_packet], %{opcode: packet.opcode}, fn ->
            state = Packet.to_message(packet) |> Message.handle(state)
            {state, %{opcode: packet.opcode}}
          end)

        %{state | conn: %{state.conn | packet_queue: rest}}

      false ->
        Logger.warning("Unimplemented: #{message_name}")
        %{state | conn: %{state.conn | packet_queue: rest}}
    end
    |> handle_packets()
  end

  @impl GenServer
  def handle_cast({:send_packet, opcode, payload}, {socket, state}) do
    message_name = ThistleTea.Opcodes.get(opcode)
    Logger.debug("Sent: #{message_name}")
    size = byte_size(payload) + 2
    header = <<size::big-size(16), opcode::little-size(16)>>

    {:ok, conn, header} = Connection.Crypto.encrypt_header(state.conn, header)
    Socket.send(socket, header <> payload)
    {:noreply, {socket, %{state | conn: conn}}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:send_update_packet, packet}, {socket, state}) do
    Util.send_update_packet(packet)
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
    Util.send_packet(%Message.SmsgDestroyObject{guid: guid})
    # TODO: remove from spawned_players/etc.?
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:start_teleport, x, y, z, map}, {socket, state}) do
    # Send player's client to loading screen to load the new map
    Util.send_packet(%Message.SmsgTransferPending{map: map, has_transport: false})

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

    Util.send_packet(%Message.SmsgNewWorld{map: map, position: %{x: x, y: y, z: z}, orientation: orientation})

    # The client responds with a MSG_MOVE_WORLDPORT_ACK message which
    # is handled in the login handler as they share the same init process
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:logout_complete, {socket, state}) do
    Util.send_packet(%Message.SmsgLogoutComplete{})
    state = Message.CmsgLogoutRequest.handle_logout(state)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:spell_complete, {socket, state}) do
    state = Message.CmsgCastSpell.handle_spell_complete(state)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:attack_swing, {socket, state}) do
    state = Message.CmsgAttackswing.handle_attack_swing(state)
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
        Util.send_packet(%Message.SmsgDestroyObject{guid: guid})
      end
    end

    for {guid, _pid} <- mobs_to_remove do
      Util.send_packet(%Message.SmsgDestroyObject{guid: guid})
    end

    for {guid, _pid} <- game_objects_to_remove do
      Util.send_packet(%Message.SmsgDestroyObject{guid: guid})
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
    {:continue, %{conn: conn, account: nil}}
  end

  @impl ThousandIsland.Handler
  def handle_close(_socket, state) do
    Logger.info("CLIENT DISCONNECTED")
    Message.CmsgLogoutRequest.handle_logout(state)
  end
end
