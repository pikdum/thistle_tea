defmodule ThistleTea.Game.Network.Server do
  @moduledoc """
  The world-server connection handler (ThousandIsland): dispatches inbound
  client messages, owns the logged-in character's state and behavior-tree
  ticks, and batches/dedupes outbound update-object blocks per send.
  """
  use ThousandIsland.Handler
  use ThistleTea.Game.Network.Opcodes, [:SMSG_AUTH_CHALLENGE, :SMSG_UPDATE_OBJECT]

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.MovementStats
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Connection
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Network.PlayerTick
  alias ThistleTea.Game.Network.Session
  alias ThistleTea.Game.Network.UpdateBatcher
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Party.MemberStats
  alias ThistleTea.Game.Party.Notifier, as: PartyNotifier
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Player.Stats, as: PlayerStats
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.World.Visibility.Tap
  alias ThousandIsland.Socket

  require Logger

  @update_flag_high_guid 0x08
  @update_flag_living 0x20
  @update_flag_has_position 0x40
  @player_tick_retry_ms 1_000

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

    case Dispatch.implemented?(packet.opcode) do
      true ->
        state =
          :telemetry.span([:thistle_tea, :handle_packet], %{opcode: packet.opcode}, fn ->
            state = Dispatch.to_message(packet) |> Message.handle(state)
            {state, %{opcode: packet.opcode}}
          end)

        %{state | conn: %{state.conn | packet_queue: rest}}

      false ->
        Logger.warning("Unimplemented: #{message_name}")
        %{state | conn: %{state.conn | packet_queue: rest}}
    end
    |> handle_packets()
  end

  defp create_update?(%UpdateObject{update_type: update_type, object: %{guid: guid}})
       when update_type in [:create_object, :create_object2] and is_integer(guid) do
    Guid.entity_type(guid) != :item
  end

  defp create_update?(%UpdateObject{}), do: false

  defp track_created_updates(state, updates) do
    created_guids =
      updates
      |> Enum.filter(&create_update?/1)
      |> MapSet.new(& &1.object.guid)

    Visibility.track_entities(state, created_guids)
  end

  defp source_tracked?(_state, nil), do: true

  defp source_tracked?(state, source_guid) when is_integer(source_guid) do
    Visibility.tracked?(state, source_guid)
  end

  defp source_tracked?(_state, _source_guid), do: false

  @impl GenServer
  def handle_cast({:send_packet, %UpdateObject{} = update, opts}, {socket, state}) do
    if source_tracked?(state, Keyword.get(opts, :source_guid)) do
      handle_cast({:send_packet, update}, {socket, state})
    else
      {:noreply, {socket, state}, socket.read_timeout}
    end
  end

  def handle_cast({:send_packet, %UpdateObject{} = update}, {socket, state}) do
    update = Tap.personalize(update, Map.get(state, :guid))
    {packet, updates} = UpdateBatcher.batch(update, Map.get(state, :guid))
    state = Network.Send.send_packet(packet, {socket, state})
    state = track_created_updates(state, updates)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  def handle_cast({:send_packet, %Packet{opcode: @smsg_update_object}}, {_socket, _state}) do
    raise "SMSG_UPDATE_OBJECT packets must be sent as UpdateObject structs"
  end

  def handle_cast({:send_packet, %Packet{opcode: @smsg_update_object}, _opts}, {_socket, _state}) do
    raise "SMSG_UPDATE_OBJECT packets must be sent as UpdateObject structs"
  end

  def handle_cast({:send_packet, %Message.SmsgDestroyObject{guid: guid} = packet}, {socket, state}) do
    if Visibility.tracked?(state, guid) do
      state = Network.Send.send_packet(packet, {socket, state})
      state = Visibility.untrack_entity(state, guid)
      {:noreply, {socket, state}, socket.read_timeout}
    else
      {:noreply, {socket, state}, socket.read_timeout}
    end
  end

  def handle_cast({:send_packet, %Message.SmsgDestroyObject{guid: guid} = packet, opts}, {socket, state}) do
    if Keyword.get(opts, :force, false) or source_tracked?(state, Keyword.get(opts, :source_guid)) do
      state = Network.Send.send_packet(packet, {socket, state})
      state = Visibility.untrack_entity(state, guid)
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
        {socket, %{character: %Character{movement_block: %MovementBlock{} = movement_block} = character} = state}
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

  def handle_cast({:receive_attack, attack}, {socket, %{character: %Character{} = character} = state}) do
    now = Time.now()

    character = PlayerCombat.mark_attacked(character, now)
    {character, events} = Combat.receive_attack(character, attack, now)
    character = EventSink.emit(character, events)

    {:noreply, {socket, %{state | character: character}}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:receive_heal, amount}, {socket, %{character: %Character{} = character} = state}) do
    character = Core.heal(character, amount)
    {:noreply, {socket, %{state | character: character}}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:receive_spell, caster, spell}, {socket, %{character: %Character{} = character} = state}) do
    now = Time.now()
    {character, events} = SpellEffect.receive(character, caster, spell, now)

    character =
      character
      |> EventSink.emit(events)

    {:noreply, {socket, %{state | character: character}}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:reward_kill, victim}, {socket, %{character: %Character{} = character} = state}) do
    state = apply_kill_reward(state, victim, kill_xp(character, victim))
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:reward_kill_share, victim, xp}, {socket, %{character: %Character{}} = state}) do
    state = apply_kill_reward(state, victim, xp)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:receive_money, amount}, {socket, %{character: %Character{} = character} = state})
      when is_integer(amount) and amount > 0 do
    player = %{character.player | coinage: character.player.coinage + amount}
    Network.send_packet(%Message.SmsgLootMoneyNotify{money: amount})
    state = InventoryUpdate.apply(state, {:ok, player})
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:request_party_stats, requester_guid}, {socket, %{character: %Character{} = character} = state}) do
    Message.SmsgPartyMemberStatsFull
    |> struct(MemberStats.from_character(character))
    |> Network.send_packet(requester_guid)

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:destroy_object, guid}, {socket, state}) do
    Network.send_packet(%Message.SmsgDestroyObject{guid: guid})
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:visibility_changed, guid}, {socket, state}) do
    state = Visibility.reevaluate_entity(state, guid)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:set_speed, rate}, {socket, %{character: %Character{} = character} = state}) do
    character = MovementStats.set_run_speed_rate(character, rate)
    character = EventSink.emit(character, [Event.movement_speed_changed(character.movement_block.run_speed)])

    {:noreply, {socket, %{state | character: character}}, {:continue, :maybe_broadcast_update}}
  end

  @impl GenServer
  def handle_cast(
        {:start_teleport, x, y, z, map},
        {socket, %{character: %Character{internal: %Internal{map: map}} = character} = state}
      ) do
    area =
      case Pathfinding.get_zone_and_area(map, {x, y, z}) do
        {_zone, area} -> area
        nil -> character.internal.area
      end

    {_x, _y, _z, o} = character.movement_block.position

    character = %{
      character
      | internal: %{character.internal | area: area},
        movement_block: %{character.movement_block | position: {x, y, z, o}, movement_flags: 0}
    }

    SpatialHash.update(:players, state.guid, map, x, y, z)

    Network.send_packet(%Message.MsgMoveTeleportAck{
      guid: state.guid,
      position: {x, y, z, o},
      timestamp: character.movement_block.timestamp || 0,
      fall_time: character.movement_block.fall_time || 0
    })

    state =
      %{state | character: character}
      |> Visibility.refresh_player()
      |> Visibility.resync_player()

    {:noreply, {socket, state}, socket.read_timeout}
  end

  def handle_cast({:start_teleport, x, y, z, map}, {socket, state}) do
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

    # Move in the spatial hash before leaving visibility so old-map observers
    # resolve the cell :left event as no-longer-visible and destroy us
    SpatialHash.update(
      :players,
      state.guid,
      character.internal.map,
      x,
      y,
      z
    )

    state = Visibility.leave_player(%{state | character: character})

    # Send player's client to loading screen to load the new map
    Network.send_packet(%Message.SmsgTransferPending{map: map, has_transport: false})

    state = %{state | ready: false}

    # Send player's client the new location
    orientation = 0

    Network.send_packet(%Message.SmsgNewWorld{map: map, position: %{x: x, y: y, z: z}, orientation: orientation})

    # The client responds with a MSG_MOVE_WORLDPORT_ACK message which
    # is handled in the login handler as they share the same init process
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:logout_complete, {socket, %{logout_timer: timer} = state}) when is_reference(timer) do
    Network.send_packet(%Message.SmsgLogoutComplete{})
    state = Session.leave_world(state)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  def handle_info(:logout_complete, {socket, state}) do
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:spell_complete, {socket, state}) do
    state = Spellcasting.complete(state)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info({:create_item, item_id, count}, {socket, state}) do
    state = Items.give(state, item_id, count)
    {:noreply, {socket, state}, socket.read_timeout}
  rescue
    error ->
      Logger.error("create_item crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info({:consume_reagents, reagents}, {socket, state}) do
    state =
      Enum.reduce(reagents, state, fn {item_id, count}, state ->
        case Inventory.remove_count(state.character.player, item_id, count, &ItemStore.get/1) do
          {:ok, result} -> InventoryUpdate.apply(state, {:ok, result})
          _ -> state
        end
      end)

    {:noreply, {socket, state}, socket.read_timeout}
  rescue
    error ->
      Logger.error("consume_reagents crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info({:deliver_spell, event}, {socket, state}) do
    EventSink.deliver_spell(event)
    {:noreply, {socket, state}, socket.read_timeout}
  rescue
    error ->
      Logger.error("deliver_spell crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:player_tick, {socket, %{character: %Character{} = character} = state}) do
    {status, character} = tick_player(character)
    character = EventSink.emit_pending(character)
    state = %{state | character: character}
    state = schedule_player_tick(state, character, status)
    {:noreply, {socket, state}, {:continue, :maybe_broadcast_update}}
  rescue
    error ->
      Logger.error("Player tick crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      ref = Process.send_after(self(), :player_tick, @player_tick_retry_ms)
      {:noreply, {socket, %{state | player_tick_ref: ref}}, socket.read_timeout}
  end

  def handle_info(:player_tick, {socket, state}) do
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info({:group, events, _info}, {socket, state}) do
    state = Visibility.handle_events(state, events)
    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_continue(:maybe_broadcast_update, {socket, state}) do
    {:noreply, {socket, maybe_broadcast_update(state)}, socket.read_timeout}
  end

  def maybe_broadcast_update(%{character: %Character{} = character} = state) do
    do_broadcast_update(%{state | character: EventSink.emit_pending(character)})
  end

  def maybe_broadcast_update(state), do: state

  defp do_broadcast_update(%{character: %Character{internal: %Internal{broadcast_update?: true}} = character} = state) do
    Core.update_object(character, :values)
    |> World.broadcast_packet(character)

    Metadata.update(state.guid, %{
      level: character.unit.level,
      alive?: Death.alive?(character),
      ghost?: Death.ghost?(character)
    })

    PartyNotifier.broadcast_stats(state.guid, character)
    internal = %{character.internal | broadcast_update?: false}
    character = %{character | internal: internal}
    PlayerTick.ensure_scheduled(%{state | character: character})
  end

  defp do_broadcast_update(state), do: state

  defp tick_player(%{internal: %Internal{behavior_tree: behavior_tree}} = character) when not is_nil(behavior_tree) do
    BT.tick(behavior_tree, character)
  end

  defp tick_player(character), do: {:running, character}

  defp schedule_player_tick(state, character, status) do
    if Tick.needs_tick?(character) do
      delay_ms = Tick.player_delay(character, status, Time.now())
      ref = Process.send_after(self(), :player_tick, delay_ms)
      %{state | player_tick_ref: ref}
    else
      %{state | player_tick_ref: nil}
    end
  end

  defp apply_kill_reward(state, victim, xp) do
    state =
      if xp > 0 do
        Network.send_packet(%Message.SmsgLogXpgain{
          target: victim.object.guid,
          total_exp: xp,
          exp_type: :kill,
          experience_without_rested: xp
        })

        {character, level_ups} = PlayerStats.gain_xp(state.character, xp)
        send_level_ups(level_ups)
        CharacterStore.put(character)

        maybe_broadcast_update(%{state | character: Core.mark_broadcast_update(character)})
      else
        state
      end

    Quests.credit_kill(state, victim.object.guid)
  end

  defp kill_xp(%Character{unit: %Unit{health: health, level: player_level}}, %{
         unit: %Unit{level: mob_level},
         internal: %Internal{creature: %Creature{} = creature}
       })
       when health > 0 do
    Experience.kill_xp(player_level, mob_level,
      experience_multiplier: creature.experience_multiplier,
      extra_flags: creature.extra_flags,
      elite?: Experience.elite_rank?(creature.rank)
    )
  end

  defp kill_xp(_character, _victim), do: 0

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

    {:continue, %Session{conn: conn}}
  end

  @impl ThousandIsland.Handler
  def handle_close(_socket, state) do
    Logger.info("CLIENT DISCONNECTED")
    Session.leave_world(state)
  end
end
