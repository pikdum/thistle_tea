defmodule ThistleTea.Game.Network.Server do
  use ThousandIsland.Handler
  use ThistleTea.Game.Network.Opcodes, [:SMSG_AUTH_CHALLENGE, :SMSG_UPDATE_OBJECT]

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Character
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Connection
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.SpatialHash
  alias ThousandIsland.Socket

  require Logger

  @update_flag_high_guid 0x08
  @update_flag_living 0x20
  @update_flag_has_position 0x40
  @player_tick_ms 100
  @update_batch_max 100

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

  def accumulate_updates(%UpdateObject{} = update, recipient_guid) do
    update
    |> accumulate_update_batch()
    |> UpdateObject.to_packet(recipient_guid)
  end

  defp accumulate_updates_with_batch(%UpdateObject{} = update, recipient_guid) do
    updates = accumulate_update_batch(update)
    {UpdateObject.to_packet(updates, recipient_guid), updates}
  end

  defp accumulate_update_batch(%UpdateObject{} = update) do
    [update]
    |> drain_pending_updates(1)
    |> Enum.reverse()
  end

  defp drain_pending_updates(updates, count) when count < @update_batch_max do
    receive do
      {:"$gen_cast", {:send_packet, %UpdateObject{} = update}} ->
        drain_pending_updates([update | updates], count + 1)
    after
      0 -> updates
    end
  end

  defp drain_pending_updates(updates, _count), do: updates

  defp create_update?(%UpdateObject{update_type: update_type, object: %{guid: guid}})
       when update_type in [:create_object, :create_object2] and is_integer(guid) do
    true
  end

  defp create_update?(%UpdateObject{}), do: false

  defp track_created_updates(state, updates) do
    created_guids =
      updates
      |> Enum.filter(&create_update?/1)
      |> MapSet.new(& &1.object.guid)

    Map.update(state, :tracked_entities, created_guids, &MapSet.union(&1, created_guids))
  end

  defp untrack_entity(state, guid) when is_integer(guid) do
    Map.update(state, :tracked_entities, MapSet.new(), &MapSet.delete(&1, guid))
  end

  defp source_tracked?(_state, nil), do: true

  defp source_tracked?(state, source_guid) when is_integer(source_guid) do
    entity_tracked?(state, source_guid)
  end

  defp source_tracked?(_state, _source_guid), do: false

  defp entity_tracked?(state, guid) when is_integer(guid) do
    state
    |> Map.get(:tracked_entities, MapSet.new())
    |> MapSet.member?(guid)
  end

  defp entity_tracked?(_state, _guid), do: false

  @impl GenServer
  def handle_cast({:send_packet, %UpdateObject{} = update}, {socket, state}) do
    {packet, updates} = accumulate_updates_with_batch(update, Map.get(state, :guid))
    state = Network.Send.send_packet(packet, {socket, state})
    state = track_created_updates(state, updates)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  def handle_cast({:send_packet, %UpdateObject{} = update, opts}, {socket, state}) do
    if source_tracked?(state, Keyword.get(opts, :source_guid)) do
      {packet, updates} = accumulate_updates_with_batch(update, Map.get(state, :guid))
      state = Network.Send.send_packet(packet, {socket, state})
      state = track_created_updates(state, updates)
      {:noreply, {socket, state}, socket.read_timeout}
    else
      {:noreply, {socket, state}, socket.read_timeout}
    end
  end

  def handle_cast({:send_packet, %Packet{opcode: @smsg_update_object}}, {_socket, _state}) do
    raise "SMSG_UPDATE_OBJECT packets must be sent as UpdateObject structs"
  end

  def handle_cast({:send_packet, %Packet{opcode: @smsg_update_object}, _opts}, {_socket, _state}) do
    raise "SMSG_UPDATE_OBJECT packets must be sent as UpdateObject structs"
  end

  def handle_cast({:send_packet, %Message.SmsgDestroyObject{guid: guid} = packet}, {socket, state}) do
    if entity_tracked?(state, guid) do
      state = Network.Send.send_packet(packet, {socket, state})
      state = untrack_entity(state, guid)
      {:noreply, {socket, state}, socket.read_timeout}
    else
      {:noreply, {socket, state}, socket.read_timeout}
    end
  end

  def handle_cast({:send_packet, %Message.SmsgDestroyObject{guid: guid} = packet, opts}, {socket, state}) do
    if source_tracked?(state, Keyword.get(opts, :source_guid)) do
      state = Network.Send.send_packet(packet, {socket, state})
      state = untrack_entity(state, guid)
      {:noreply, {socket, state}, socket.read_timeout}
    else
      {:noreply, {socket, state}, socket.read_timeout}
    end
  end

  def handle_cast({:send_packet, packet, opts}, {socket, state}) do
    if source_tracked?(state, Keyword.get(opts, :source_guid)) do
      state = Network.Send.send_packet(packet, {socket, state})
      {:noreply, {socket, state}, socket.read_timeout}
    else
      {:noreply, {socket, state}, socket.read_timeout}
    end
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
    |> Network.send_packet(pid)

    {:noreply, {socket, state}, socket.read_timeout}
  end

  def handle_cast({:receive_attack, attack}, {socket, %{character: character} = state}) do
    damage = Combat.attack_damage(attack)
    character = Core.take_damage(character, damage)

    character =
      EventSink.emit(
        character,
        Combat.attacker_state_update(Map.get(attack, :caster, 0), state.guid, damage, attack)
      )

    {:noreply, {socket, %{state | character: character}}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:reward_kill, victim}, {socket, %{character: %Character{} = character} = state}) do
    xp = kill_xp(character, victim)

    state =
      if xp > 0 do
        Network.send_packet(%Message.SmsgLogXpgain{
          target: victim.object.guid,
          total_exp: xp,
          exp_type: :kill
        })

        {character, level_ups} = Character.gain_xp(character, xp)
        send_level_ups(level_ups)

        Character.save(character)
        Metadata.update(state.guid, %{level: character.unit.level})

        update = Core.update_object(character, :values)
        Network.send_packet(update)
        World.broadcast_packet(update, character, include_self?: false)

        %{state | character: character}
      else
        state
      end

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:destroy_object, guid}, {socket, state}) do
    Network.send_packet(%Message.SmsgDestroyObject{guid: guid})
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
      character.internal.map,
      x,
      y,
      z
    )

    state =
      Map.merge(state, %{
        character: character,
        ready: false,
        tracked_entities: MapSet.new()
      })

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
    character = EventSink.emit_pending(character)
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

    old_players = tracked_entities(state, :player)
    old_mobs = tracked_entities(state, :mob)
    old_game_objects = tracked_entities(state, :game_object)

    new_players =
      SpatialHash.query(:players, c.internal.map, x, y, z, 250)
      |> MapSet.new(fn {guid, _distance} -> guid end)

    new_mobs =
      SpatialHash.query(:mobs, c.internal.map, x, y, z, 250)
      |> MapSet.new(fn {guid, _distance} -> guid end)

    new_game_objects =
      SpatialHash.query(:game_objects, c.internal.map, x, y, z, 250)
      |> MapSet.new(fn {guid, _distance} -> guid end)

    players_to_remove = MapSet.difference(old_players, new_players)
    mobs_to_remove = MapSet.difference(old_mobs, new_mobs)
    game_objects_to_remove = MapSet.difference(old_game_objects, new_game_objects)

    players_to_add = MapSet.difference(new_players, old_players)
    mobs_to_add = MapSet.difference(new_mobs, old_mobs)
    game_objects_to_add = MapSet.difference(new_game_objects, old_game_objects)

    # TODO: update a reverse mapping, so mobs know nearby players?
    for guid <- players_to_remove do
      if guid != state.guid do
        Network.send_packet(%Message.SmsgDestroyObject{guid: guid})
      end
    end

    for guid <- mobs_to_remove do
      Network.send_packet(%Message.SmsgDestroyObject{guid: guid})
    end

    for guid <- game_objects_to_remove do
      Network.send_packet(%Message.SmsgDestroyObject{guid: guid})
    end

    for guid <- players_to_add do
      if guid != state.guid do
        Entity.request_update_from(guid, state.guid)
      end
    end

    for guid <- mobs_to_add do
      Entity.request_update_from(guid, state.guid)
    end

    for guid <- game_objects_to_add do
      Entity.request_update_from(guid, state.guid)
    end

    # TODO: redundant, refactor out?
    player_guids = MapSet.to_list(new_players)
    mob_guids = MapSet.to_list(new_mobs)

    state =
      Map.merge(state, %{
        player_guids: player_guids,
        mob_guids: mob_guids
      })

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:spawn_objects, {socket, state}) do
    {:noreply, {socket, state}, socket.read_timeout}
  end

  defp tracked_entities(state, entity_type) do
    state
    |> Map.get(:tracked_entities, MapSet.new())
    |> Enum.filter(&(Guid.entity_type(&1) == entity_type))
    |> MapSet.new()
  end

  @impl GenServer
  def handle_continue(
        :maybe_broadcast_update,
        {socket, %{character: %ThistleTea.Character{internal: %Internal{broadcast_update?: true}} = character} = state}
      ) do
    Core.update_object(character, :values)
    |> World.broadcast_packet(character)

    Metadata.update(state.guid, %{alive?: not Core.dead?(character)})
    internal = %{character.internal | broadcast_update?: false}
    character = %{character | internal: internal}

    {:noreply, {socket, %{state | character: character}}, socket.read_timeout}
  end

  def handle_continue(:maybe_broadcast_update, {socket, state}) do
    {:noreply, {socket, state}, socket.read_timeout}
  end

  defp tick_player(%{internal: %Internal{behavior_tree: behavior_tree}} = character) when not is_nil(behavior_tree) do
    BT.tick(behavior_tree, character)
  end

  defp tick_player(character), do: {:running, character}

  defp schedule_player_tick(state, character, status) do
    if player_needs_tick?(character) do
      delay_ms = player_tick_delay(character, status)
      ref = Process.send_after(self(), :player_tick, delay_ms)
      Map.put(state, :player_tick_ref, ref)
    else
      Map.put(state, :player_tick_ref, nil)
    end
  end

  defp player_tick_delay(_character, {:running, delay_ms}) when is_integer(delay_ms) and delay_ms > 0 do
    delay_ms
  end

  defp player_tick_delay(character, _status) do
    if player_only_needs_aura_tick?(character) do
      case Aura.next_event_at(character) do
        at when is_integer(at) -> max(at - Time.now(), 0)
        _ -> @player_tick_ms
      end
    else
      @player_tick_ms
    end
  end

  defp player_needs_tick?(%{internal: %Internal{casting: casting}}) when is_map(casting) do
    true
  end

  defp player_needs_tick?(%{internal: %Internal{in_combat: true}, unit: %Unit{target: target}})
       when is_integer(target) and target > 0 do
    true
  end

  defp player_needs_tick?(%{unit: %Unit{auras: [_ | _]}}), do: true

  defp player_needs_tick?(_character), do: false

  defp player_only_needs_aura_tick?(%{
         internal: %Internal{casting: casting, in_combat: in_combat},
         unit: %Unit{target: target, auras: [_ | _]}
       }) do
    not is_map(casting) and not (in_combat == true and is_integer(target) and target > 0)
  end

  defp player_only_needs_aura_tick?(_character), do: false

  defp kill_xp(%Character{unit: %Unit{health: health, level: player_level}}, %{
         unit: %Unit{level: mob_level},
         internal: %Internal{} = internal
       })
       when health > 0 do
    Experience.kill_xp(player_level, mob_level,
      experience_multiplier: internal.experience_multiplier,
      extra_flags: internal.extra_flags,
      elite?: elite?(internal.rank)
    )
  end

  defp kill_xp(_character, _victim), do: 0

  defp elite?(rank) when rank in [1, 2, 3], do: true
  defp elite?(_rank), do: false

  defp send_level_ups(level_ups) do
    Enum.each(level_ups, fn level_up ->
      Network.send_packet(struct(Message.SmsgLevelupInfo, level_up))
    end)
  end

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
