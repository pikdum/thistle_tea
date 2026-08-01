defmodule ThistleTea.Game.Entity.Server.Player do
  @moduledoc """
  Owning GenServer for a logged-in player character.

  It runs client commands, entity messages, behavior-tree ticks, timers, and
  world lifecycle transitions. The attached network connection only transports
  encoded packets.
  """
  use GenServer

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Request, as: ObservationRequest
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.BoundaryResult
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Dueling
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Hunter
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Loot.Release
  alias ThistleTea.Game.Entity.Logic.Loot.Reservation
  alias ThistleTea.Game.Entity.Logic.MovementStats
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.PlayerFlags
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.Rest
  alias ThistleTea.Game.Entity.Logic.Shaman
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Entity.Logic.StealthDetection
  alias ThistleTea.Game.Entity.Logic.Transport, as: TransportLogic
  alias ThistleTea.Game.Entity.Server.AIEnvironment
  alias ThistleTea.Game.Entity.Server.NavigationResolver
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Monitor, as: CompanionMonitor
  alias ThistleTea.Game.Entity.Server.Player.PacketSink
  alias ThistleTea.Game.Entity.Server.Player.ServerMovement
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Entity.Server.Player.TickScheduler
  alias ThistleTea.Game.Entity.Server.PlayerSupervisor
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Party.MemberStats
  alias ThistleTea.Game.Party.Notifier, as: PartyNotifier
  alias ThistleTea.Game.Player.CompanionVisibility
  alias ThistleTea.Game.Player.Enchantments
  alias ThistleTea.Game.Player.Exploration, as: PlayerExploration
  alias ThistleTea.Game.Player.GameObjects, as: PlayerGameObjects
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.Player.Login
  alias ThistleTea.Game.Player.Looting
  alias ThistleTea.Game.Player.Mail
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Player.Reputation, as: PlayerReputation
  alias ThistleTea.Game.Player.Rest, as: PlayerRest
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Player.Stats, as: PlayerStats
  alias ThistleTea.Game.Player.Taxi, as: PlayerTaxi
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.AggroProbe
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ChaseWatch
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: ItemEnchantmentLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellPetAura, as: SpellPetAuraLoader
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.System.Duel, as: DuelSystem
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.World.Transports
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.WorldRef

  require Logger

  @update_flag_high_guid 0x08
  @update_flag_living 0x20
  @update_flag_has_position 0x40
  @player_tick_retry_ms 1_000

  def child_spec({_account, _connection_pid, character_guid} = args) do
    %{
      id: {__MODULE__, character_guid},
      start: {__MODULE__, :start_link, [args]},
      restart: :temporary
    }
  end

  def start_link({account, connection_pid, character_guid}) do
    GenServer.start_link(
      __MODULE__,
      {account, connection_pid, character_guid},
      name: ThistleTea.Game.Entity.Registry.via(character_guid)
    )
  end

  def login(account, connection_pid, character_guid) when is_pid(connection_pid) and is_integer(character_guid) do
    DynamicSupervisor.start_child(PlayerSupervisor, {__MODULE__, {account, connection_pid, character_guid}})
  end

  def handle_message(pid, message) when is_pid(pid) do
    GenServer.call(pid, {:client_message, message})
  end

  def disconnect(pid) when is_pid(pid) do
    GenServer.call(pid, :disconnect)
  catch
    :exit, _reason -> :ok
  end

  @impl GenServer
  def init({account, connection_pid, character_guid}) do
    Process.monitor(connection_pid)

    state =
      %State{account: account, connection_pid: connection_pid}
      |> Login.enter_world(character_guid)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:client_message, message}, _from, state) do
    {:reply, :ok, Message.handle(message, state)}
  end

  def handle_call(:disconnect, _from, state) do
    {:stop, :normal, :ok, State.leave_world(state)}
  end

  @impl GenServer
  def handle_cast({:send_packet, message, opts}, state), do: {:noreply, PacketSink.send(state, message, opts)}

  def handle_cast({:send_packet, message}, state), do: {:noreply, PacketSink.send(state, message)}

  def handle_cast({:start_script, steps, target_guid}, %State{character: %Character{}} = state)
      when is_list(steps) and is_integer(target_guid) do
    {:noreply, run_script(state, steps, target_guid), {:continue, :maybe_broadcast_update}}
  rescue
    error ->
      Logger.error("start_script crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:mail_delivery, token, mail}, state) do
    state = Mail.receive_delivery(state, token, mail)
    {:noreply, state}
  rescue
    error ->
      Logger.error("mail delivery crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_cast({:duel_update, {:requested, payload}}, %{character: %Character{} = character} = state) do
    character = Dueling.requested(character, payload)
    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:duel_update, {:started, payload}}, %{character: %Character{} = character} = state) do
    character = Dueling.started(character, payload)
    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:duel_update, {:finished, payload}}, %{character: %Character{} = character} = state) do
    {character, events} = Dueling.finish(character, payload)
    character = EventSink.emit(character, events)
    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  @impl GenServer
  def handle_cast(
        {:send_update_to, pid},
        %{character: %Character{movement_block: %MovementBlock{} = movement_block} = character} = state
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

    {:noreply, state}
  end

  def handle_cast({:receive_attack, attack}, %{character: %Character{} = character} = state) do
    now = Time.now()
    alive? = Death.alive?(character)

    character =
      cond do
        not alive? ->
          character

        PlayerCombat.undetectable?(character, now) ->
          character

        true ->
          character = PlayerCombat.mark_attacked(character, now, PlayerReputation.faction_id(attack.caster))
          {character, events} = Combat.receive_attack(character, attack, now)
          EventSink.emit(character, events)
      end

    if alive?, do: notify_defensive_pet(character, attack.caster)

    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:receive_heal, amount}, %{character: %Character{} = character} = state) do
    character = Core.heal(character, amount)
    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:drain_power, power_type}, %{character: %Character{} = character} = state) do
    character = Resources.drain_power(character, power_type)
    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:grant_power, power_type, amount}, %{character: %Character{} = character} = state) do
    character = Resources.gain_power(character, power_type, amount)
    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast(
        {:summon_request, summoner_guid, zone_id, world, {x, y, z}},
        %{character: %Character{internal: internal} = character} = state
      ) do
    auto_decline_ms = 120_000

    pending = %{
      summoner_guid: summoner_guid,
      world: world,
      position: {x, y, z},
      expires_at: Time.now() + auto_decline_ms
    }

    Network.send_packet(%Message.SmsgSummonRequest{
      summoner_guid: summoner_guid,
      zone_id: zone_id || 0,
      auto_decline_ms: auto_decline_ms
    })

    character = %{character | internal: %{internal | pending_summon: pending}}
    {:noreply, %{state | character: character}}
  end

  def handle_cast(
        {:start_game_object_channel, game_object_guid, %Spell{} = spell, duration_ms},
        %{character: %Character{} = character} = state
      ) do
    character = Casting.start_game_object_channel(character, game_object_guid, spell, duration_ms, Time.now())
    character = EventSink.emit_pending(character)
    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:finish_game_object_channel, game_object_guid}, %{character: %Character{} = character} = state) do
    character = Casting.finish_game_object_channel(character, game_object_guid)
    character = EventSink.emit_pending(character)
    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:attack_outcome, payload}, %{character: %Character{} = character} = state) do
    spell = spellbook_spell(character, Map.get(payload, :spell_id))
    weapon_proc = Enchantments.weapon_proc(character)

    ppm =
      case weapon_proc do
        %{effect: %{spell_id: spell_id}} -> ItemEnchantmentLoader.proc_ppm(spell_id)
        _ -> 0.0
      end

    character =
      character
      |> AttackFeedback.receive(payload, spell, Time.now())
      |> Shaman.trigger_weapon_enchant(payload, weapon_proc, ppm)

    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:spell_outcome, payload}, %{character: %Character{} = character} = state) do
    spell = spellbook_spell(character, Map.get(payload, :spell_id))
    character = SpellFeedback.receive(character, payload, spell, Time.now())

    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:threat_ref_gained, mob_guid, incarnation_id}, %{character: %Character{} = character} = state) do
    character =
      character
      |> PlayerCombat.gain_threat_ref(mob_guid, incarnation_id)
      |> PlayerCombat.mark_temporary_at_war(PlayerReputation.faction_id(mob_guid))

    state = TickScheduler.ensure_scheduled(%{state | character: character})
    {:noreply, state, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:threat_ref_lost, mob_guid, incarnation_id}, %{character: %Character{} = character} = state) do
    character = PlayerCombat.lose_threat_ref(character, mob_guid, incarnation_id)
    state = TickScheduler.ensure_scheduled(%{state | character: character})
    {:noreply, state}
  end

  def handle_cast({:receive_spell, caster, spell}, %{character: %Character{} = character} = state) do
    now = Time.now()
    harmful? = Spell.harmful?(spell)
    alive? = Death.alive?(character)
    character = apply_incoming_spell(character, caster, spell, now, harmful?, alive?)

    state = %{state | character: character}
    state = if harmful? and alive?, do: TickScheduler.ensure_scheduled(state), else: state
    if harmful? and alive?, do: notify_defensive_pet(character, spell_caster_guid(caster))

    {:noreply, state, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:receive_spell_outcome, caster_guid, spell, outcome}, %{character: %Character{} = character} = state) do
    harmful? = Spell.harmful?(spell)

    state =
      if harmful? and not Death.alive?(character) do
        state
      else
        now = Time.now()

        character =
          if harmful?,
            do: PlayerCombat.mark_attacked(character, now, PlayerReputation.faction_id(caster_guid)),
            else: character

        {character, events} = SpellEffect.receive_outcome(character, caster_guid, spell, outcome, now)
        character = EventSink.emit(character, events)
        state = %{state | character: character}
        if harmful?, do: TickScheduler.ensure_scheduled(state), else: state
      end

    if harmful? and Death.alive?(character), do: notify_defensive_pet(state.character, caster_guid)

    {:noreply, state, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:trigger_spell, spell_id, target_guid, opts}, %{character: %Character{} = character} = state)
      when is_integer(spell_id) and is_integer(target_guid) and is_list(opts) do
    event = Effects.trigger_spell(character.object.guid, character.unit.level || 1, target_guid, spell_id, opts)
    character = EventSink.emit(character, event)
    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:remove_aura, spell_id, caster_guid}, %{character: %Character{} = character} = state) do
    {character, events} = Aura.remove_source_spell(character, spell_id, caster_guid, Time.now())
    character = EventSink.emit(character, events)
    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:delay_aura, spell_id, caster_guid, delay_ms}, %{character: %Character{} = character} = state) do
    character = Aura.delay_source_spell(character, spell_id, caster_guid, delay_ms, Time.now())
    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:reward_kill, victim}, %{character: %Character{} = character} = state) do
    xp = kill_xp(character, victim)
    state = if xp > 0, do: trigger_kill_procs(state, victim), else: state
    state = apply_kill_reward(state, victim, xp)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:reward_kill_share, victim, xp}, %{character: %Character{}} = state) do
    state = apply_kill_reward(state, victim, xp)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:receive_money, amount}, %{character: %Character{} = character} = state)
      when is_integer(amount) and amount > 0 do
    player = %{character.player | coinage: character.player.coinage + amount}
    Network.send_packet(%Message.SmsgLootMoneyNotify{money: amount})
    state = InventoryUpdate.apply(state, {:ok, player})
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:request_party_stats, requester_guid}, %{character: %Character{} = character} = state) do
    Message.SmsgPartyMemberStatsFull
    |> struct(MemberStats.from_character(character))
    |> Network.send_packet(requester_guid)

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:party_leader_changed, leader?}, %{character: %Character{} = character} = state)
      when is_boolean(leader?) do
    character = PlayerFlags.set_group_leader(character, leader?)

    if PlayerFlags.group_leader?(character) == PlayerFlags.group_leader?(state.character) do
      {:noreply, state}
    else
      character = Core.mark_broadcast_update(character)
      {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
    end
  rescue
    _error -> {:noreply, state}
  end

  def handle_cast({:party_leader_changed, _leader?}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:destroy_object, guid}, state) do
    Network.send_packet(%Message.SmsgDestroyObject{guid: guid})
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:visibility_changed, guid}, state) do
    state = Visibility.reevaluate_entity(state, guid)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:set_speed, rate}, %{character: %Character{} = character} = state) do
    character = MovementStats.set_run_speed_rate(character, rate)
    character = EventSink.emit(character, [Effects.movement_speed_changed(character.movement_block.run_speed)])

    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  @impl GenServer
  def handle_cast({:start_teleport, x, y, z, map}, %{character: %Character{} = character} = state) do
    {_current_x, _current_y, _current_z, orientation} = character.movement_block.position
    handle_cast({:start_teleport, x, y, z, orientation, map}, state)
  end

  def handle_cast({:start_teleport, x, y, z, orientation, map_id}, state) when is_integer(map_id) do
    {:ok, world} = InstanceSystem.destination(map_id, state.guid)
    handle_cast({:start_teleport, x, y, z, orientation, world}, state)
  end

  def handle_cast(
        {:start_teleport, x, y, z, orientation, world},
        %{character: %Character{internal: %Internal{world: world}}} = state
      ) do
    state = state |> cancel_authoritative_movement() |> detach_transport()
    state = state |> disengage_for_world_transition() |> suspend_companion_for_teleport()
    character = state.character

    {zone, area} = destination_zone_and_area(character, world.map_id, {x, y, z})

    character =
      character
      |> PlayerRest.evaluate_zone(zone)
      |> mark_rest_transition(character)
      |> then(fn character ->
        %{
          character
          | internal: %{character.internal | area: area},
            movement_block: %{character.movement_block | position: {x, y, z, orientation}, movement_flags: 0}
        }
      end)

    Presence.relocate(character)

    Network.send_packet(%Message.MsgMoveTeleportAck{
      guid: state.guid,
      position: {x, y, z, orientation},
      timestamp: character.movement_block.timestamp || 0,
      fall_time: character.movement_block.fall_time || 0
    })

    state =
      %{state | character: character}
      |> Visibility.refresh_player()
      |> Visibility.resync_player()
      |> maybe_broadcast_update()

    {:noreply, state}
  end

  def handle_cast({:start_teleport, x, y, z, orientation, %WorldRef{} = world}, state) do
    state = state |> cancel_authoritative_movement() |> detach_transport()
    DuelSystem.disconnect(state.guid)
    state = state |> disengage_for_world_transition() |> suspend_companion_for_teleport()
    previous_world = state.character.internal.world
    character = state.character
    {zone, area} = destination_zone_and_area(character, world.map_id, {x, y, z})

    character =
      character
      |> PlayerRest.evaluate_zone(zone)
      |> mark_rest_transition(character)
      |> then(fn character ->
        %{
          character
          | internal: %{character.internal | area: area, world: world},
            movement_block: %{character.movement_block | position: {x, y, z, orientation}}
        }
      end)

    Presence.relocate(character)

    state = Visibility.leave_player(%{state | character: character})
    InstanceSystem.leave(state.guid, previous_world)

    # Send player's client to loading screen to load the new map
    Network.send_packet(%Message.SmsgTransferPending{map: world.map_id, has_transport: false})

    state = State.prepare_worldport(%{state | ready: false}, previous_world, world)

    # Send player's client the new location
    Network.send_packet(%Message.SmsgNewWorld{
      map: world.map_id,
      position: %{x: x, y: y, z: z},
      orientation: orientation
    })

    Network.send_packet(%Message.SmsgUpdateInstanceOwnership{player_is_saved_to_a_raid: false})

    # The client responds with a MSG_MOVE_WORLDPORT_ACK message which
    # is handled in the login handler as they share the same init process
    {:noreply, state}
  end

  def handle_cast({:finish_repop, token}, state) do
    state = MovementControl.finish_repop(state, token)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        {:DOWN, token, :process, _pid, _reason},
        %State{companion_monitor: %CompanionMonitor{token: token}} = state
      ) do
    {:ok, entity_ref, state} = CompanionOwner.process_down(state, token)
    {:noreply, project_companion_detachment(state, entity_ref), {:continue, :maybe_broadcast_update}}
  end

  def handle_info({:DOWN, _monitor, :process, connection_pid, _reason}, %State{connection_pid: connection_pid} = state) do
    {:stop, :normal, State.leave_world(state)}
  end

  def handle_info(
        {:transport_pose,
         %{guid: transport_guid, world: %WorldRef{} = world, position: transport_position} = transport},
        %State{
          character: %Character{
            movement_block: %MovementBlock{transport_guid: transport_guid, transport_position: local_position}
          }
        } = state
      )
      when is_tuple(local_position) do
    position = TransportLogic.passenger_world_position(local_position, transport_position)

    if state.character.internal.world == world do
      movement_block = %{state.character.movement_block | position: position, timestamp: 0}
      character = %{state.character | movement_block: movement_block}
      Presence.relocate(character)

      {x, y, z, _orientation} = position
      AggroProbe.notify_player_moved(state.guid, world, {x, y, z})
      ChaseWatch.notify_moved(state.guid, {x, y, z})

      state =
        %{state | character: character}
        |> PlayerRest.check_tavern_exit()
        |> PlayerExploration.check_movement()
        |> Visibility.refresh_player()

      {:noreply, state}
    else
      {:noreply, transport_worldport(state, transport, position)}
    end
  end

  def handle_info({:transport_pose, _transport}, state) do
    {:noreply, state}
  end

  def handle_info({:transport_lost, transport_guid}, %State{character: %Character{} = character} = state) do
    if character.movement_block.transport_guid == transport_guid do
      character = %{character | movement_block: MovementBlock.clear_transport(character.movement_block)}
      Presence.relocate(character)
      {:noreply, %{state | character: character, transport_refresh_pending: nil}}
    else
      {:noreply, state}
    end
  end

  def handle_info(:restore_companion, state) do
    {:noreply, Login.restore_companion(state)}
  end

  def handle_info({:taxi_arrived, token}, state) do
    {:noreply, PlayerTaxi.arrive(state, token)}
  rescue
    error ->
      Logger.error("taxi arrival crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_info({:taxi_progress, token}, state) do
    {:noreply, PlayerTaxi.progress(state, token)}
  rescue
    error ->
      Logger.error("taxi progress crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_info({:server_movement_arrived, token}, state) do
    {:noreply, ServerMovement.finish(state, token)}
  rescue
    error ->
      Logger.error("server movement arrival crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_info({:send_taxi_path, path_id}, state) do
    {:noreply, PlayerTaxi.start_path(state, path_id)}
  rescue
    error ->
      Logger.error("script taxi path crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_info({:ai_script_steps, steps, target_guid}, %State{character: %Character{}} = state)
      when is_list(steps) and is_integer(target_guid) do
    {:noreply, run_script(state, steps, target_guid), {:continue, :maybe_broadcast_update}}
  rescue
    error ->
      Logger.error("ai_script_steps crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_info({:mail_delivery_ready, deliver_at}, state) do
    {:noreply, Mail.delivery_ready(state, deliver_at)}
  rescue
    error ->
      Logger.error("mail delivery timer crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_info({:finish_repop_timeout, token}, state) do
    state = MovementControl.finish_repop(state, token, true)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:logout_complete, %{logout_timer: timer} = state) when is_reference(timer) do
    state = State.leave_world(state)
    {:stop, {:shutdown, :logout}, state}
  end

  def handle_info(:logout_complete, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:spell_complete, state) do
    state = Spellcasting.complete(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:loot_award, loot_guid, %Reservation{} = reservation}, state) do
    {:noreply, Looting.accept_reservation(state, loot_guid, reservation)}
  rescue
    error ->
      release = %Release{token: reservation.token, actor_guid: reservation.actor_guid}
      Entity.loot_reservation_result(loot_guid, release)
      Logger.error("loot award crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  @impl GenServer
  def handle_info({:create_item, item_id, count}, state) do
    state = Items.give(state, item_id, count)
    {:noreply, state}
  rescue
    error ->
      Logger.error("create_item crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  @impl GenServer
  def handle_info({:open_gameobject_loot, object_guid}, state) do
    state = PlayerGameObjects.open_chest(state, object_guid)
    {:noreply, state}
  rescue
    error ->
      Logger.error("open_gameobject_loot crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  @impl GenServer
  def handle_info(%Commands.ChargePathResolved{} = command, %{character: %Character{}} = state) do
    {:noreply, ServerMovement.start(state, command)}
  end

  def handle_info(%Commands.FarsightStarted{guid: guid} = command, %{character: %Character{} = character} = state) do
    character = BoundaryResult.apply(character, command)
    state = %{state | character: character} |> Visibility.set_viewpoint(guid)
    {:noreply, state, {:continue, :maybe_broadcast_update}}
  end

  def handle_info(%Commands.ChannelGameObjectStarted{} = command, %{character: %Character{} = character} = state) do
    character = BoundaryResult.apply(character, command)
    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_info(%Commands.TotemStarted{} = command, %{character: %Character{} = character} = state) do
    character = BoundaryResult.apply(character, command)
    {:noreply, %{state | character: character}}
  end

  def handle_info({:consume_cast_item, item_guid}, state) do
    state = Items.consume(state, item_guid)
    {:noreply, state}
  rescue
    error ->
      Logger.error("consume_cast_item crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        {:feed_pet, item_guid, pet_guid, trigger_spell_id, range_yards},
        %{character: %Character{} = character} = state
      ) do
    state = feed_pet(state, character, item_guid, pet_guid, trigger_spell_id, range_yards)
    {:noreply, state}
  rescue
    error ->
      Logger.error("feed_pet crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_info({:farsight_removed, guid}, %{character: %Character{} = character} = state) do
    {character, removed?} =
      if character.player.farsight == guid do
        character =
          %{character | player: %{character.player | farsight: 0}}
          |> Core.mark_broadcast_update()

        {character, true}
      else
        {character, false}
      end

    state = %{state | character: character}
    state = if removed?, do: Visibility.reset_viewpoint(state), else: state
    state = maybe_broadcast_update(state)
    {:noreply, state}
  end

  def handle_info({:viewpoint_granted, guid}, %{character: %Character{} = character} = state) do
    character =
      %{character | player: %{character.player | farsight: guid}}
      |> Core.mark_broadcast_update()

    state = %{state | character: character} |> Visibility.set_viewpoint(guid)
    {:noreply, state, {:continue, :maybe_broadcast_update}}
  end

  def handle_info({:viewpoint_released, guid}, %{character: %Character{} = character} = state) do
    {character, released?} =
      if character.player.farsight == guid do
        character =
          %{character | player: %{character.player | farsight: 0}}
          |> Core.mark_broadcast_update()

        {character, true}
      else
        {character, false}
      end

    state = %{state | character: character}
    state = if released?, do: Visibility.reset_viewpoint(state), else: state
    {:noreply, state, {:continue, :maybe_broadcast_update}}
  end

  def handle_info({:target_moved, guid}, state) do
    {:noreply, Visibility.refresh_viewpoint(state, guid)}
  end

  @impl GenServer
  def handle_info({:enchant_item, item_guid, spell, enchantment_id, duration_ms}, state) do
    state = Enchantments.apply_temporary(state, item_guid, spell, enchantment_id, duration_ms)
    {:noreply, state}
  rescue
    error ->
      Logger.error("enchant_item crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  @impl GenServer
  def handle_info({:expire_item_enchantment, item_guid, token}, state) do
    state = Enchantments.expire(state, item_guid, token)
    {:noreply, state}
  rescue
    error ->
      Logger.error("expire_item_enchantment crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  @impl GenServer
  def handle_info({:consume_reagents, reagents}, state) do
    state =
      Enum.reduce(reagents, state, fn {item_id, count}, state ->
        case Inventory.remove_count(state.character.player, item_id, count, &ItemStore.get/1) do
          {:ok, result} -> InventoryUpdate.apply(state, {:ok, result})
          _ -> state
        end
      end)

    {:noreply, state}
  rescue
    error ->
      Logger.error("consume_reagents crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  @impl GenServer
  def handle_info({:tame_pet, entry}, %{character: %Character{} = character} = state)
      when is_integer(entry) and entry > 0 do
    character = EventSink.emit(character, Effects.summon_pet(character.object.guid, entry, 1515))
    {:noreply, %{state | character: character}}
  rescue
    error ->
      Logger.error("tame_pet crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  @impl GenServer
  def handle_info({:deliver_spell, event}, state) do
    EventSink.deliver_spell(event)
    {:noreply, state}
  rescue
    error ->
      Logger.error("deliver_spell crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_info(%Attachment{} = attachment, %State{character: %Character{}} = state) do
    state =
      state
      |> CompanionVisibility.prepare_attachment(attachment)
      |> CompanionOwner.attach(attachment)
      |> project_companion_attachment(attachment)

    {:noreply, state, {:continue, {:finish_companion_attach, attachment}}}
  end

  def handle_info({:reputation_change, faction_id, value}, %State{} = state) do
    {:noreply, PlayerReputation.reward_spell(state, faction_id, value)}
  end

  def handle_info({:quest_cast_credit, target_guids, spell_id}, %State{} = state) do
    {:noreply, Quests.credit_cast(state, target_guids, spell_id)}
  end

  def handle_info({:quest_event_credit, quest_id}, %State{} = state) do
    {:noreply, Quests.credit_event(state, quest_id)}
  end

  def handle_info({:quest_event_credit, quest_id, group?, distance, world_object_guid}, %State{} = state) do
    {:noreply, Quests.credit_scripted_event(state, quest_id, group?, distance, world_object_guid)}
  end

  def handle_info({:quest_group_event_credit, quest_id, distance, world_object_guid}, %State{} = state) do
    {:noreply, Quests.credit_scripted_event_member(state, quest_id, distance, world_object_guid)}
  end

  def handle_info({:quest_fail, quest_id, group?}, %State{} = state) do
    {:noreply, Quests.fail(state, quest_id, group?)}
  end

  def handle_info({:quest_fail_member, quest_id}, %State{} = state) do
    {:noreply, Quests.fail_member(state, quest_id)}
  end

  def handle_info({:quest_interaction_credit, target_guid}, %State{} = state) do
    {:noreply, Quests.credit_entity_interaction(state, target_guid)}
  end

  def handle_info({:quest_kill_credit, creature_entry, group?}, %State{} = state) do
    {:noreply, Quests.credit_scripted_kill(state, creature_entry, group?)}
  end

  def handle_info({:quest_group_kill_credit, creature_entry, source_guid}, %State{} = state) do
    {:noreply, Quests.credit_scripted_kill_member(state, creature_entry, source_guid)}
  end

  def handle_info({:quest_timer_expired, quest_id, expires_at_ms}, %State{} = state) do
    {:noreply, Quests.expire_timed(state, quest_id, expires_at_ms)}
  end

  def handle_info({:stop_attack_factions, faction_ids}, %State{character: %Character{} = character} = state)
      when is_list(faction_ids) do
    if PlayerReputation.faction_id(character.unit.target) in faction_ids do
      {character, effects} = PlayerCombat.stop_attack(character)
      character = EventSink.emit(character, effects)
      state = TickScheduler.ensure_scheduled(%{state | character: character})
      {:noreply, state, {:continue, :maybe_broadcast_update}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:control_released, controlled_guid}, %State{} = state) do
    case CompanionOwner.detach(state, controlled_guid, :released) do
      {:ok, entity_ref, state} ->
        {:noreply, project_companion_detachment(state, entity_ref), {:continue, :maybe_broadcast_update}}

      :stale ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:player_tick, %{character: %Character{} = character} = state) do
    now = Time.now()
    {status, character} = tick_player(character, now)
    character = NavigationResolver.resolve(character, now)
    character = EventSink.emit_pending(character)
    state = %{state | character: character}
    state = schedule_player_tick(state, character, status, now)
    {:noreply, state, {:continue, :maybe_broadcast_update}}
  rescue
    error ->
      Logger.error("Player tick crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      ref = Process.send_after(self(), :player_tick, @player_tick_retry_ms)
      {:noreply, %{state | player_tick_ref: ref}}
  end

  def handle_info(:player_tick, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:group, events, _info}, state) do
    state = Visibility.handle_events(state, events)
    {:noreply, state}
  end

  @impl GenServer
  def handle_continue({:finish_companion_attach, %Attachment{} = attachment}, state) do
    state = maybe_broadcast_update(state)
    {:noreply, CompanionVisibility.finish_attachment(state, attachment)}
  end

  def handle_continue(:maybe_broadcast_update, state) do
    {:noreply, maybe_broadcast_update(state)}
  end

  def maybe_broadcast_update(%{character: %Character{}} = state) do
    state
    |> cancel_cast_if_dead()
    |> sync_character_metadata()
    |> then(fn state -> %{state | character: EventSink.emit_pending(state.character)} end)
    |> do_broadcast_update()
  end

  def maybe_broadcast_update(state), do: state

  defp run_script(%State{character: %Character{} = character} = state, steps, target_guid) do
    now = Time.now()

    request =
      ObservationRequest.new([target_guid], Script.observation_radius(steps),
        game_object_radius: Script.game_object_observation_radius(steps),
        script_conditions: Script.termination_conditions(steps),
        script_targets: Script.target_requests(steps)
      )

    context = AIEnvironment.context(character, now, request)
    {character, _blackboard} = Script.run(character, Blackboard.new(), steps, target_guid, context)
    %{state | character: character}
  end

  defp cancel_cast_if_dead(%{character: %Character{internal: %Internal{casting: casting}} = character} = state)
       when not is_nil(casting) do
    if Core.dead?(character), do: Spellcasting.cancel(state), else: state
  end

  defp cancel_cast_if_dead(state), do: state

  defp do_broadcast_update(%{character: %Character{internal: %Internal{broadcast_update?: true}} = character} = state) do
    Core.update_object(character, :values)
    |> World.broadcast_packet(character)

    PartyNotifier.broadcast_stats(state.guid, character)
    internal = %{character.internal | broadcast_update?: false}
    character = %{character | internal: internal}
    TickScheduler.ensure_scheduled(%{state | character: character})
  end

  defp do_broadcast_update(state), do: state

  defp sync_character_metadata(%{guid: guid, character: %Character{} = character} = state) when is_integer(guid) do
    detection = StealthDetection.target_metadata(character)

    Presence.sync(
      character,
      %{
        level: character.unit.level,
        alive?: Death.alive?(character),
        ghost?: Death.ghost?(character),
        in_combat: character.internal.in_combat == true,
        rooted?: character.internal.rooted? == true,
        health_pct: Core.health_pct(character),
        mana_pct: Core.mana_pct(character),
        power_type: character.unit.power_type,
        unit_flags: character.unit.flags,
        shapeshift_form: character.unit.shapeshift_form,
        controlled_guid: Character.controlled_guid(character),
        duel_opponent_guid: Dueling.opponent_guid(character),
        duel_started?: Dueling.active?(character),
        contested_pvp?: PlayerFlags.contested_pvp?(character),
        aura_sources: Aura.source_spells(character),
        aura_stacks: Aura.spell_stacks(character),
        crowd_controlled?: Aura.crowd_controlled?(character),
        dispel_options: Aura.dispel_options(character),
        attacker_spell_hit_chance: Aura.attacker_spell_hit_chance(character),
        reputation: PlayerReputation.projection(character)
      }
      |> Map.merge(detection)
    )

    state
  end

  defp sync_character_metadata(state), do: state

  defp tick_player(%{internal: %Internal{behavior_tree: behavior_tree}} = character, now)
       when not is_nil(behavior_tree) and is_integer(now) do
    BehaviorRunner.tick(behavior_tree, character, AIEnvironment.context(character, now))
  end

  defp tick_player(character, _now), do: {:running, character}

  defp schedule_player_tick(state, character, status, now) do
    if Tick.needs_tick?(character) do
      delay_ms = Tick.player_delay(character, status, now)
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

  defp feed_pet(state, character, item_guid, pet_guid, trigger_spell_id, range_yards) do
    with %DataItem{} = item <- owned_item(character, item_guid),
         {:ok, pet} <- Entity.call(pet_guid, :feed_info),
         :ok <- feed_pet_in_range(character, pet_guid, range_yards),
         {:ok, benefit} <- Hunter.feed_benefit(%{item: DataItem.template(item), pet: pet}),
         %Spell{} = spell <- SpellLoader.load(trigger_spell_id) do
      state = Items.consume(state, item_guid)
      spell = Hunter.apply_food_benefit(spell, benefit)
      context = CastContext.from_caster(state.character, spell, pet_guid)
      Entity.receive_spell(pet_guid, context, spell)
      state
    else
      _ -> state
    end
  end

  defp owned_item(%Character{player: player}, item_guid) when is_integer(item_guid) do
    case Inventory.find_position(player, item_guid, &ItemStore.get/1) do
      {_bag, _slot} -> ItemStore.get(item_guid)
      _ -> nil
    end
  end

  defp owned_item(_character, _item_guid), do: nil

  defp feed_pet_in_range(character, pet_guid, range_yards) when is_number(range_yards) and range_yards > 0 do
    case World.distance_between(character, pet_guid) do
      distance when is_number(distance) and distance <= range_yards ->
        if World.line_of_sight?(character, pet_guid), do: :ok, else: {:error, :line_of_sight}

      _ ->
        {:error, :out_of_range}
    end
  end

  defp feed_pet_in_range(_character, _pet_guid, _range_yards), do: :ok

  defp passive_pet_aura_events(%Character{unit: %Unit{auras: holders, level: level}}, pet_guid) when is_list(holders) do
    pet_entry = Guid.entry(pet_guid)

    holders
    |> Enum.flat_map(fn %{spell: %Spell{id: spell_id}} -> SpellPetAuraLoader.pet_aura_ids(spell_id, pet_entry) end)
    |> Enum.uniq()
    |> Enum.map(&Effects.trigger_spell(pet_guid, level || 1, pet_guid, &1))
  end

  defp passive_pet_aura_events(_character, _pet_guid), do: []

  defp project_companion_attachment(%State{character: %Character{} = character} = state, %Attachment{
         kind: kind,
         entity_ref: %EntityRef{guid: guid}
       })
       when kind in [:hunter_pet, :guardian] do
    {character, aura_events} = Aura.remove_spells(character, [18_789, 18_790, 18_791, 18_792, 25_228], Time.now())

    character =
      character
      |> EventSink.emit(aura_events)
      |> EventSink.emit(passive_pet_aura_events(character, guid))
      |> Core.mark_broadcast_update()

    %{state | character: character}
  end

  defp project_companion_attachment(%State{character: %Character{} = character} = state, %Attachment{
         kind: :possession,
         entity_ref: %EntityRef{guid: guid}
       }) do
    character =
      %{character | player: %{character.player | farsight: guid}}
      |> Core.mark_broadcast_update()

    Network.send_packet(%Message.SmsgClientControlUpdate{guid: guid, allow_movement?: true})

    %{state | character: character, active_mover_guid: guid}
    |> Visibility.set_viewpoint(guid)
  end

  defp project_companion_attachment(%State{character: %Character{} = character} = state, %Attachment{}) do
    %{state | character: Core.mark_broadcast_update(character)}
  end

  defp project_companion_detachment(%State{character: %Character{} = character} = state, %EntityRef{} = entity_ref) do
    possession? = state.active_mover_guid == entity_ref.guid

    if possession? do
      Network.send_packet(%Message.SmsgClientControlUpdate{guid: entity_ref.guid, allow_movement?: false})
    end

    character =
      if possession? do
        %{character | player: %{character.player | farsight: 0}}
      else
        character
      end

    {character, aura_events} = Aura.remove_spells(character, Enum.uniq([25_228, entity_ref.spell_id]), Time.now())

    character =
      character
      |> EventSink.emit(aura_events)
      |> Core.mark_broadcast_update()

    state = %{
      state
      | character: character,
        active_mover_guid: if(possession?, do: state.guid, else: state.active_mover_guid)
    }

    state = if possession?, do: Visibility.reset_viewpoint(state), else: state
    CompanionVisibility.clear(state)
  end

  defp trigger_kill_procs(state, victim) do
    {character, events} = Aura.reactions(state.character, :kill, %{victim_guid: victim.object.guid, now: Time.now()})
    %{state | character: EventSink.emit(character, events)}
  end

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
    |> maybe_reward_kill_reputation(victim)
    |> Quests.credit_kill(victim.object.guid)
    |> maybe_broadcast_update()
  end

  defp maybe_reward_kill_reputation(state, %{internal: %Internal{pet: nil}} = victim) do
    PlayerReputation.reward_kill(state, Guid.entry(victim.object.guid), victim.unit.level)
  end

  defp maybe_reward_kill_reputation(state, _victim), do: state

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

  defp notify_defensive_pet(%Character{} = character, attacker_guid) when is_integer(attacker_guid) do
    case Entity.pid(Character.controlled_guid(character)) do
      pid when is_pid(pid) -> send(pid, {:owner_attacked, attacker_guid})
      _ -> :ok
    end
  end

  defp notify_defensive_pet(%Character{}, _attacker_guid), do: :ok

  defp apply_incoming_spell(%Character{} = character, _caster, _spell, _now, true, false), do: character

  defp apply_incoming_spell(%Character{} = character, caster, spell, now, true, true) do
    if PlayerCombat.undetectable?(character, now) do
      character
    else
      character =
        PlayerCombat.mark_attacked(
          character,
          now,
          caster |> spell_caster_guid() |> PlayerReputation.faction_id()
        )

      {character, events} = SpellEffect.receive(character, caster, spell, now)
      notify_spell_hit_target(caster, character.object.guid, spell, events)
      EventSink.emit(character, events)
    end
  end

  defp apply_incoming_spell(%Character{} = character, caster, spell, now, false, _alive?) do
    {character, events} = SpellEffect.receive(character, caster, spell, now)
    notify_spell_hit_target(caster, character.object.guid, spell, events)
    EventSink.emit(character, events)
  end

  defp notify_spell_hit_target(caster, target_guid, %Spell{} = spell, events)
       when is_integer(target_guid) and is_list(events) do
    caster_guid = spell_caster_guid(caster)

    if Guid.entity_type(caster_guid) == :mob and SpellEffect.successful_hit?(events) do
      Entity.spell_hit_target(caster_guid, target_guid, spell)
    end
  end

  defp spell_caster_guid(%{caster_guid: guid}) when is_integer(guid), do: guid
  defp spell_caster_guid(guid) when is_integer(guid), do: guid
  defp spell_caster_guid(_caster), do: nil

  defp suspend_companion_for_teleport(%State{character: %Character{} = character} = state) do
    if is_integer(Companion.summon_guid(character)) do
      state
      |> CompanionVisibility.clear()
      |> CompanionOwner.suspend()
    else
      state
    end
  end

  defp disengage_for_world_transition(%State{character: %Character{} = character} = state) do
    {character, effects} = PlayerCombat.disengage(character)
    %{state | character: EventSink.emit(character, effects)}
  end

  defp destination_zone_and_area(%Character{} = character, map_id, position) do
    case Pathfinding.get_zone_and_area(map_id, position) do
      {zone, area} ->
        {zone, area}

      _unknown ->
        zone = PlayerRest.default_zone(map_id)
        {zone, fallback_destination_area(character, map_id, zone)}
    end
  end

  defp fallback_destination_area(
         %Character{internal: %Internal{world: %WorldRef{map_id: map_id}, area: area}},
         map_id,
         _zone
       ), do: area

  defp fallback_destination_area(%Character{}, _map_id, zone) when is_integer(zone), do: zone
  defp fallback_destination_area(%Character{}, _map_id, _zone), do: 0

  defp mark_rest_transition(%Character{} = character, %Character{} = previous) do
    if character == previous, do: character, else: Core.mark_broadcast_update(character)
  end

  defp detach_transport(%State{character: %Character{} = character} = state) do
    Transports.leave(character)
    character = %{character | movement_block: MovementBlock.clear_transport(character.movement_block)}
    %{state | character: character, transport_refresh_pending: nil}
  end

  defp detach_transport(state), do: state

  defp cancel_authoritative_movement(%State{} = state) do
    state
    |> ServerMovement.cancel()
    |> PlayerTaxi.disconnect()
  end

  defp transport_worldport(%State{} = state, %{entry: entry, world: %WorldRef{} = world}, {x, y, z, orientation}) do
    DuelSystem.disconnect(state.guid)

    state =
      state
      |> ServerMovement.cancel()
      |> prepare_transport_worldport()
      |> disengage_for_world_transition()
      |> suspend_companion_for_teleport()

    previous_world = state.character.internal.world
    character = state.character
    {zone, area} = destination_zone_and_area(character, world.map_id, {x, y, z})

    {transport_x, transport_y, transport_z, transport_orientation} =
      character.movement_block.transport_position

    character =
      character
      |> PlayerRest.evaluate_zone(zone)
      |> mark_rest_transition(character)
      |> then(fn character ->
        %{
          character
          | internal: %{character.internal | area: area, world: world},
            movement_block: %{character.movement_block | position: {x, y, z, orientation}, timestamp: 0}
        }
      end)

    Presence.relocate(character)
    state = Visibility.leave_player(%{state | character: character})
    InstanceSystem.leave(state.guid, previous_world)

    Network.send_packet(%Message.SmsgTransferPending{
      map: world.map_id,
      has_transport: true,
      transport: entry,
      transport_map: previous_world.map_id
    })

    state = State.prepare_worldport(%{state | ready: false}, previous_world, world)

    Network.send_packet(%Message.SmsgNewWorld{
      map: world.map_id,
      position: %{x: transport_x, y: transport_y, z: transport_z},
      orientation: transport_orientation
    })

    Network.send_packet(%Message.SmsgUpdateInstanceOwnership{player_is_saved_to_a_raid: false})
    state
  end

  defp prepare_transport_worldport(%State{character: %Character{} = character} = state) do
    now = Time.now()
    {character, control_events} = Aura.remove_aura_types(character, [:mod_confuse, :mod_fear], now)
    character = EventSink.emit(character, control_events)
    state = %{state | character: character}

    if Death.alive?(character) do
      maybe_broadcast_update(state)
    else
      World.stop_entity(Corpse.guid_for(state.guid))
      {character, resurrection_events} = Death.resurrect(character, 1.0, now)
      character = EventSink.emit(character, resurrection_events)
      maybe_broadcast_update(%{state | character: character})
    end
  end

  @impl GenServer
  def terminate(_reason, %State{character: %Character{}} = state) do
    State.leave_world(state)
    :ok
  end

  def terminate(_reason, _state), do: :ok
end
