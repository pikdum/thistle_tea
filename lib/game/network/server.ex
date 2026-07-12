defmodule ThistleTea.Game.Network.Server do
  @moduledoc """
  The world-server connection handler (ThousandIsland): dispatches inbound
  client messages, owns the logged-in character's state and behavior-tree
  ticks, and batches/dedupes outbound update-object blocks per send.
  """
  use ThousandIsland.Handler
  use ThistleTea.Game.Network.Opcodes, [:SMSG_AUTH_CHALLENGE, :SMSG_UPDATE_OBJECT]

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.MovementStats
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.Rest
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.StealthDetection
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
  alias ThistleTea.Game.Player.Enchantments
  alias ThistleTea.Game.Player.GameObjects, as: PlayerGameObjects
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Player.Stats, as: PlayerStats
  alias ThistleTea.Game.Spell
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

    character =
      if PlayerCombat.undetectable?(character, now) do
        character
      else
        character = PlayerCombat.mark_attacked(character, now)
        {character, events} = Combat.receive_attack(character, attack, now)
        EventSink.emit(character, events)
      end

    notify_defensive_pet(character, attack.caster)

    {:noreply, {socket, %{state | character: character}}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:receive_heal, amount}, {socket, %{character: %Character{} = character} = state}) do
    character = Core.heal(character, amount)
    {:noreply, {socket, %{state | character: character}}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast(:drain_rage, {socket, %{character: %Character{} = character} = state}) do
    character = Resources.drain_rage(character)
    {:noreply, {socket, %{state | character: character}}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:grant_power, power_type, amount}, {socket, %{character: %Character{} = character} = state}) do
    character = Resources.gain_power(character, power_type, amount)
    {:noreply, {socket, %{state | character: character}}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:attack_outcome, payload}, {socket, %{character: %Character{} = character} = state}) do
    spell = spellbook_spell(character, Map.get(payload, :spell_id))
    character = AttackFeedback.receive(character, payload, spell, Time.now())
    {:noreply, {socket, %{state | character: character}}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:threat_ref_gained, mob_guid}, {socket, %{character: %Character{} = character} = state}) do
    character = PlayerCombat.gain_threat_ref(character, mob_guid)
    state = PlayerTick.ensure_scheduled(%{state | character: character})
    {:noreply, {socket, state}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:threat_ref_lost, mob_guid}, {socket, %{character: %Character{} = character} = state}) do
    character = PlayerCombat.lose_threat_ref(character, mob_guid)
    state = PlayerTick.ensure_scheduled(%{state | character: character})
    {:noreply, {socket, state}, socket.read_timeout}
  end

  def handle_cast({:receive_spell, caster, spell}, {socket, %{character: %Character{} = character} = state}) do
    now = Time.now()
    harmful? = Spell.harmful?(spell)

    character =
      if harmful? and PlayerCombat.undetectable?(character, now) do
        character
      else
        character = if harmful?, do: PlayerCombat.mark_attacked(character, now), else: character
        {character, events} = SpellEffect.receive(character, caster, spell, now)
        EventSink.emit(character, events)
      end

    state = %{state | character: character}
    state = if harmful?, do: PlayerTick.ensure_scheduled(state), else: state
    if harmful?, do: notify_defensive_pet(character, spell_caster_guid(caster))

    {:noreply, {socket, state}, {:continue, :maybe_broadcast_update}}
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
  def handle_info({:open_gameobject_loot, object_guid}, {socket, state}) do
    state = PlayerGameObjects.open_chest(state, object_guid)
    {:noreply, {socket, state}, socket.read_timeout}
  rescue
    error ->
      Logger.error("open_gameobject_loot crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info({:consume_cast_item, item_guid}, {socket, state}) do
    state = Items.consume(state, item_guid)
    {:noreply, {socket, state}, socket.read_timeout}
  rescue
    error ->
      Logger.error("consume_cast_item crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info({:enchant_item, item_guid, spell, enchantment_id, duration_ms}, {socket, state}) do
    state = Enchantments.apply_temporary(state, item_guid, spell, enchantment_id, duration_ms)
    {:noreply, {socket, state}, socket.read_timeout}
  rescue
    error ->
      Logger.error("enchant_item crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info({:expire_item_enchantment, item_guid, token}, {socket, state}) do
    state = Enchantments.expire(state, item_guid, token)
    {:noreply, {socket, state}, socket.read_timeout}
  rescue
    error ->
      Logger.error("expire_item_enchantment crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
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

  def handle_info(
        {:pet_attached, pet_guid, _spell_id, pet_spells},
        {socket, %{character: %Character{unit: %Unit{}} = character} = state}
      ) do
    {character, aura_events} = Aura.remove_spells(character, [18_789, 18_790, 18_791, 18_792, 25_228], Time.now())

    character =
      character
      |> then(fn character -> %{character | unit: %{character.unit | summon: pet_guid}} end)
      |> EventSink.emit(aura_events)
      |> Core.mark_broadcast_update()

    Network.send_packet(Message.SmsgPetSpells.for_pet(pet_guid, pet_spells))
    {:noreply, {socket, %{state | character: character}}, {:continue, :maybe_broadcast_update}}
  end

  def handle_info(
        {:pet_removed, pet_guid},
        {socket, %{character: %Character{unit: %Unit{summon: pet_guid}} = character} = state}
      ) do
    {character, aura_events} = Aura.remove_spells(character, [25_228], Time.now())

    character =
      character
      |> then(fn character -> %{character | unit: %{character.unit | summon: 0}} end)
      |> EventSink.emit(aura_events)
      |> Core.mark_broadcast_update()

    Network.send_packet(Message.SmsgPetSpells.clear())
    {:noreply, {socket, %{state | character: character}}, {:continue, :maybe_broadcast_update}}
  end

  def handle_info({:pet_removed, _pet_guid}, {socket, state}) do
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

  def maybe_broadcast_update(%{character: %Character{}} = state) do
    state
    |> sync_character_metadata()
    |> then(fn state -> %{state | character: EventSink.emit_pending(state.character)} end)
    |> do_broadcast_update()
  end

  def maybe_broadcast_update(state), do: state

  defp do_broadcast_update(%{character: %Character{internal: %Internal{broadcast_update?: true}} = character} = state) do
    Core.update_object(character, :values)
    |> World.broadcast_packet(character)

    PartyNotifier.broadcast_stats(state.guid, character)
    internal = %{character.internal | broadcast_update?: false}
    character = %{character | internal: internal}
    PlayerTick.ensure_scheduled(%{state | character: character})
  end

  defp do_broadcast_update(state), do: state

  defp sync_character_metadata(%{guid: guid, character: %Character{} = character} = state) when is_integer(guid) do
    detection = StealthDetection.target_metadata(character)

    Metadata.update(
      guid,
      %{
        level: character.unit.level,
        alive?: Death.alive?(character),
        ghost?: Death.ghost?(character),
        health_pct: Core.health_pct(character),
        unit_flags: character.unit.flags,
        shapeshift_form: character.unit.shapeshift_form,
        aura_sources: Aura.source_spells(character)
      }
      |> Map.merge(detection)
    )

    state
  end

  defp sync_character_metadata(state), do: state

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

  defp spellbook_spell(%Character{internal: %Internal{spellbook: spellbook}}, spell_id)
       when is_map(spellbook) and is_integer(spell_id) do
    Map.get(spellbook, spell_id)
  end

  defp spellbook_spell(_character, _spell_id), do: nil

  defp apply_kill_reward(state, victim, xp) do
    character = Reactive.clear_combo_target(state.character, victim.object.guid)
    state = %{state | character: character}

    state =
      if xp > 0 do
        {character, rested_bonus} = Rest.spend(state.character, xp, Time.now())
        total_xp = xp + rested_bonus

        Network.send_packet(%Message.SmsgLogXpgain{
          target: victim.object.guid,
          total_exp: total_xp,
          exp_type: :kill,
          experience_without_rested: xp
        })

        {character, level_ups} = PlayerStats.gain_xp(character, total_xp)
        send_level_ups(level_ups)
        CharacterStore.put(character)

        maybe_broadcast_update(%{state | character: Core.mark_broadcast_update(character)})
      else
        state
      end

    state
    |> Quests.credit_kill(victim.object.guid)
    |> maybe_broadcast_update()
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

  defp notify_defensive_pet(%Character{unit: %Unit{summon: pet_guid}}, attacker_guid)
       when is_integer(pet_guid) and pet_guid > 0 and is_integer(attacker_guid) do
    case Entity.pid(pet_guid) do
      pid when is_pid(pid) -> send(pid, {:owner_attacked, attacker_guid})
      _ -> :ok
    end
  end

  defp notify_defensive_pet(%Character{}, _attacker_guid), do: :ok

  defp spell_caster_guid(%{caster_guid: guid}) when is_integer(guid), do: guid
  defp spell_caster_guid(guid) when is_integer(guid), do: guid
  defp spell_caster_guid(_caster), do: nil

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
