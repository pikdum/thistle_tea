defmodule ThistleTea.Game.Network.Server do
  use ThousandIsland.Handler
  use ThistleTea.Game.Network.Opcodes, [:SMSG_AUTH_CHALLENGE, :SMSG_UPDATE_OBJECT]

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Connection
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.SpatialHash
  alias ThousandIsland.Socket

  require Logger

  @update_flag_high_guid 0x08
  @update_flag_living 0x20
  @update_flag_has_position 0x40
  @player_tick_ms 100

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
    message_name = Opcodes.get(packet.opcode)

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

  def accumulate_updates(size, body) do
    receive do
      {:"$gen_cast",
       {:send_packet,
        %Packet{opcode: @smsg_update_object, payload: <<next_size::little-size(32), 0, next_body::binary>>}}}
      when size + next_size <= 100 ->
        accumulate_updates(size + next_size, body <> next_body)
    after
      0 -> %Packet{opcode: @smsg_update_object, payload: <<size::little-size(32), 0, body::binary>>}
    end
  end

  @impl GenServer
  def handle_cast(
        {:send_packet, %Packet{opcode: @smsg_update_object, payload: <<size::little-size(32), 0, body::binary>>}},
        {socket, state}
      ) do
    packet = accumulate_updates(size, body)
    state = Network.Send.send_packet(packet, {socket, state})
    {:noreply, {socket, state}, socket.read_timeout}
  end

  def handle_cast({:send_packet, packet}, {socket, state}) do
    state = Network.Send.send_packet(packet, {socket, state})
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast(
        {:send_update_to, pid},
        {socket,
         %{character: %ThistleTea.Character{movement_block: %MovementBlock{} = movement_block} = character} = state}
      ) do
    update_flag = @update_flag_high_guid ||| @update_flag_living ||| @update_flag_has_position
    movement_block = %{movement_block | update_flag: update_flag}

    %UpdateObject{
      update_type: :create_object2,
      object_type: :player
    }
    |> struct(Map.from_struct(character))
    |> Map.put(:movement_block, movement_block)
    |> UpdateObject.to_packet()
    |> Network.send_packet(pid)

    {:noreply, {socket, state}, socket.read_timeout}
  end

  def handle_cast({:receive_attack, attack}, {socket, %{character: character} = state}) do
    damage = Combat.attack_damage(attack)
    character = Core.take_damage(character, damage)

    Combat.attacker_state_update(Map.get(attack, :caster, 0), state.guid, damage, attack)
    |> World.broadcast_packet(character)

    Core.update_packet(character, :values)
    |> World.broadcast_packet(character)

    {:noreply, {socket, %{state | character: character}}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:destroy_object, guid}, {socket, state}) do
    Network.send_packet(%Message.SmsgDestroyObject{guid: guid})
    # TODO: remove from spawned_players/etc.?
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:start_teleport, x, y, z, map}, {socket, state}) do
    # Send player's client to loading screen to load the new map
    Network.send_packet(%Message.SmsgTransferPending{map: map, has_transport: false})

    # Update player's location
    area =
      case Pathfinding.get_zone_and_area(map, {x, y, z}) do
        {_zone, area} -> area
        nil -> state.character.internal.area
      end

    character = state.character

    character = %{
      character
      | internal: %{character.internal | area: area, map: map},
        movement_block: %{character.movement_block | position: {x, y, z, 0.0}}
    }

    SpatialHash.update(
      :players,
      state.guid,
      self(),
      character.internal.map,
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

    Network.send_packet(%Message.SmsgNewWorld{map: map, position: %{x: x, y: y, z: z}, orientation: orientation})

    # The client responds with a MSG_MOVE_WORLDPORT_ACK message which
    # is handled in the login handler as they share the same init process
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:logout_complete, {socket, state}) do
    Network.send_packet(%Message.SmsgLogoutComplete{})
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
  def handle_info(:player_tick, {socket, %{character: character} = state}) do
    {status, character} = tick_player(character)
    state = Map.put(state, :character, character)
    state = schedule_player_tick(state, character, status)
    {:noreply, {socket, state}, socket.read_timeout}
  rescue
    _ -> {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:spawn_objects, {socket, %{character: c, ready: true} = state}) do
    # TODO: add telemetry for periodic tasks
    {x, y, z, _o} = c.movement_block.position

    old_players = Map.get(state, :spawned_players, MapSet.new())
    old_mobs = Map.get(state, :spawned_mobs, MapSet.new())
    old_game_objects = Map.get(state, :spawned_game_objects, MapSet.new())

    new_players =
      SpatialHash.query(:players, c.internal.map, x, y, z, 250)
      |> MapSet.new(fn {guid, pid, _distance} -> {guid, pid} end)

    new_mobs =
      SpatialHash.query(:mobs, c.internal.map, x, y, z, 250)
      |> MapSet.new(fn {guid, pid, _distance} -> {guid, pid} end)

    new_game_objects =
      SpatialHash.query(:game_objects, c.internal.map, x, y, z, 250)
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
        Network.send_packet(%Message.SmsgDestroyObject{guid: guid})
      end
    end

    for {guid, _pid} <- mobs_to_remove do
      Network.send_packet(%Message.SmsgDestroyObject{guid: guid})
    end

    for {guid, _pid} <- game_objects_to_remove do
      Network.send_packet(%Message.SmsgDestroyObject{guid: guid})
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

  defp tick_player(%{internal: %Internal{behavior_tree: behavior_tree}} = character) when not is_nil(behavior_tree) do
    BT.tick(behavior_tree, character)
  end

  defp tick_player(character), do: {:running, character}

  defp schedule_player_tick(state, character, status) do
    if player_needs_tick?(character) do
      delay_ms = player_tick_delay(status)
      ref = Process.send_after(self(), :player_tick, delay_ms)
      Map.put(state, :player_tick_ref, ref)
    else
      Map.put(state, :player_tick_ref, nil)
    end
  end

  defp player_tick_delay({:running, delay_ms}) when is_integer(delay_ms) and delay_ms > 0 do
    delay_ms
  end

  defp player_tick_delay(_status), do: @player_tick_ms

  defp player_needs_tick?(%{internal: %Internal{casting: casting}}) when is_map(casting) do
    true
  end

  defp player_needs_tick?(%{internal: %Internal{in_combat: true}, unit: %Unit{target: target}})
       when is_integer(target) and target > 0 do
    true
  end

  defp player_needs_tick?(_character), do: false

  @impl ThousandIsland.Handler
  def handle_connection(socket, _) do
    conn = %Connection{}

    Socket.send(
      socket,
      <<6::big-size(16), @smsg_auth_challenge::little-size(16)>> <> conn.seed
    )

    {:continue, %{conn: conn, account: nil}}
  end

  @impl ThousandIsland.Handler
  def handle_close(_socket, state) do
    Logger.info("CLIENT DISCONNECTED")
    Message.CmsgLogoutRequest.handle_logout(state)
  end
end
