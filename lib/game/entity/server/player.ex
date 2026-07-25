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
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Dueling
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Hunter
  alias ThistleTea.Game.Entity.Logic.Inventory
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
  alias ThistleTea.Game.Entity.Server.Player.PacketSink
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Entity.Server.Player.TickScheduler
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Party.MemberStats
  alias ThistleTea.Game.Party.Notifier, as: PartyNotifier
  alias ThistleTea.Game.Player.Enchantments
  alias ThistleTea.Game.Player.GameObjects, as: PlayerGameObjects
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.Player.Login
  alias ThistleTea.Game.Player.Mail
  alias ThistleTea.Game.Player.Quests
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Player.Stats, as: PlayerStats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.EntitySupervisor
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: ItemEnchantmentLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellPetAura, as: SpellPetAuraLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Duel, as: DuelSystem
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
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
    DynamicSupervisor.start_child(EntitySupervisor, {__MODULE__, {account, connection_pid, character_guid}})
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

    character =
      if PlayerCombat.undetectable?(character, now) do
        character
      else
        character = PlayerCombat.mark_attacked(character, now)
        {character, events} = Combat.receive_attack(character, attack, now)
        EventSink.emit(character, events)
      end

    notify_defensive_pet(character, attack.caster)

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
    character = SpellBT.start_game_object_channel(character, game_object_guid, spell, duration_ms, Time.now())
    character = EventSink.emit_pending(character)
    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:finish_game_object_channel, game_object_guid}, %{character: %Character{} = character} = state) do
    character = SpellBT.finish_game_object_channel(character, game_object_guid)
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
    character = PlayerCombat.gain_threat_ref(character, mob_guid, incarnation_id)
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

    character =
      if harmful? and PlayerCombat.undetectable?(character, now) do
        character
      else
        character = if harmful?, do: PlayerCombat.mark_attacked(character, now), else: character
        {character, events} = SpellEffect.receive(character, caster, spell, now)
        EventSink.emit(character, events)
      end

    state = %{state | character: character}
    state = if harmful?, do: TickScheduler.ensure_scheduled(state), else: state
    if harmful?, do: notify_defensive_pet(character, spell_caster_guid(caster))

    {:noreply, state, {:continue, :maybe_broadcast_update}}
  end

  def handle_cast({:receive_spell_outcome, caster_guid, spell, outcome}, %{character: %Character{} = character} = state) do
    now = Time.now()
    character = PlayerCombat.mark_attacked(character, now)
    {character, events} = SpellEffect.receive_outcome(character, caster_guid, spell, outcome, now)
    character = EventSink.emit(character, events)
    state = %{state | character: character} |> TickScheduler.ensure_scheduled()
    notify_defensive_pet(character, caster_guid)

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
    state = suspend_pet_for_teleport(state)
    character = state.character

    area =
      case Pathfinding.get_zone_and_area(world.map_id, {x, y, z}) do
        {_zone, area} -> area
        nil -> character.internal.area
      end

    character = %{
      character
      | internal: %{character.internal | area: area},
        movement_block: %{character.movement_block | position: {x, y, z, orientation}, movement_flags: 0}
    }

    SpatialHash.update(:players, state.guid, world, x, y, z)

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

    {:noreply, state}
  end

  def handle_cast({:start_teleport, x, y, z, orientation, %WorldRef{} = world}, state) do
    DuelSystem.disconnect(state.guid)
    state = suspend_pet_for_teleport(state)
    previous_world = state.character.internal.world

    # Update player's location
    area =
      case Pathfinding.get_zone_and_area(world.map_id, {x, y, z}) do
        {_zone, area} -> area
        nil -> state.character.internal.area
      end

    character = state.character

    character = %{
      character
      | internal: %{character.internal | area: area, world: world},
        movement_block: %{character.movement_block | position: {x, y, z, orientation}}
    }

    # Move in the spatial hash before leaving visibility so old-map observers
    # resolve the cell :left event as no-longer-visible and destroy us
    SpatialHash.update(
      :players,
      state.guid,
      character.internal.world,
      x,
      y,
      z
    )

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
  def handle_info({:DOWN, _monitor, :process, connection_pid, _reason}, %State{connection_pid: connection_pid} = state) do
    {:stop, :normal, State.leave_world(state)}
  end

  def handle_info(:restore_active_pet, state) do
    {:noreply, Login.restore_active_pet(state)}
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
    state = PacketSink.send(state, %Message.SmsgLogoutComplete{})
    connection_pid = state.connection_pid
    state = State.leave_world(state)
    GenServer.cast(connection_pid, {:player_logged_out, self()})
    {:stop, :normal, state}
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

  def handle_info(
        {:pet_attached, %UpdateObject{object: %{guid: pet_guid}} = pet_update, spell_id, pet_spells},
        %{character: %Character{unit: %Unit{}}} = state
      ) do
    state = PacketSink.ensure_created(state, pet_update)
    character = state.character
    {character, aura_events} = Aura.remove_spells(character, [18_789, 18_790, 18_791, 18_792, 25_228], Time.now())

    character =
      character
      |> then(fn character ->
        %{
          character
          | unit: %{character.unit | summon: pet_guid},
            internal: %{
              character.internal
              | active_pet_entry: Guid.entry(pet_guid),
                active_pet_spell_id: spell_id
            }
        }
      end)
      |> EventSink.emit(aura_events)
      |> EventSink.emit(passive_pet_aura_events(character, pet_guid))
      |> Core.mark_broadcast_update()

    {:noreply, %{state | character: character}, {:continue, {:finish_pet_attach, pet_guid, pet_spells}}}
  end

  def handle_info(
        {:control_granted, controlled_guid, spell_id, spells, possess?},
        %{character: %Character{unit: %Unit{}} = character} = state
      ) do
    character =
      %{character | unit: %{character.unit | charm: controlled_guid}}
      |> Core.mark_broadcast_update()

    {character, state} =
      if possess? do
        character = %{character | player: %{character.player | farsight: controlled_guid}}
        Network.send_packet(%Message.SmsgClientControlUpdate{guid: controlled_guid, allow_movement?: true})
        {character, %{state | active_mover_guid: controlled_guid, active_control_spell_id: spell_id}}
      else
        {character, %{state | active_control_spell_id: spell_id}}
      end

    state =
      %{state | character: character}
      |> then(fn state -> if possess?, do: Visibility.set_viewpoint(state, controlled_guid), else: state end)

    {:noreply, state, {:continue, {:finish_pet_attach, controlled_guid, spells}}}
  end

  def handle_info(
        {:control_released, controlled_guid},
        %{character: %Character{unit: %Unit{charm: controlled_guid}} = character} = state
      ) do
    possessed? = state.active_mover_guid == controlled_guid

    {character, state} =
      if possessed? do
        Network.send_packet(%Message.SmsgClientControlUpdate{guid: controlled_guid, allow_movement?: false})

        character = %{character | player: %{character.player | farsight: 0}}
        {character, %{state | active_mover_guid: state.guid}}
      else
        {character, state}
      end

    {character, aura_events} =
      case state.active_control_spell_id do
        spell_id when is_integer(spell_id) -> Aura.remove_spells(character, [spell_id], Time.now())
        _ -> {character, []}
      end

    character =
      %{character | unit: %{character.unit | charm: 0}}
      |> EventSink.emit(aura_events)
      |> Core.mark_broadcast_update()

    state = %{state | character: character, active_control_spell_id: nil}
    state = if possessed?, do: Visibility.reset_viewpoint(state), else: state
    Network.send_packet(Message.SmsgPetSpells.clear())
    {:noreply, state, {:continue, :maybe_broadcast_update}}
  end

  def handle_info({:control_released, _controlled_guid}, state) do
    {:noreply, state}
  end

  def handle_info({:pet_removed, pet_guid}, %{character: %Character{unit: %Unit{summon: pet_guid}} = character} = state) do
    {character, aura_events} = Aura.remove_spells(character, [25_228], Time.now())

    hunter_pet? = character.internal.active_pet_spell_id == 1515

    character =
      character
      |> then(fn character ->
        %{
          character
          | unit: %{character.unit | summon: 0},
            internal: %{
              character.internal
              | active_pet_entry: if(hunter_pet?, do: character.internal.active_pet_entry),
                active_pet_spell_id: if(hunter_pet?, do: 1515)
            }
        }
      end)
      |> EventSink.emit(aura_events)
      |> Core.mark_broadcast_update()

    Network.send_packet(Message.SmsgPetSpells.clear())
    {:noreply, %{state | character: character}, {:continue, :maybe_broadcast_update}}
  end

  def handle_info({:pet_removed, _pet_guid}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:player_tick, %{character: %Character{} = character} = state) do
    {status, character} = tick_player(character)
    character = EventSink.emit_pending(character)
    state = %{state | character: character}
    state = schedule_player_tick(state, character, status)
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
  def handle_continue({:finish_pet_attach, pet_guid, pet_spells}, state) do
    state = maybe_broadcast_update(state)
    Network.send_packet(Message.SmsgPetSpells.for_pet(pet_guid, pet_spells))
    {:noreply, state}
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

    Metadata.update(
      guid,
      %{
        level: character.unit.level,
        alive?: Death.alive?(character),
        ghost?: Death.ghost?(character),
        health_pct: Core.health_pct(character),
        power_type: character.unit.power_type,
        unit_flags: character.unit.flags,
        shapeshift_form: character.unit.shapeshift_form,
        world: character.internal.world,
        area: character.internal.area,
        controlled_guid: Character.controlled_guid(character),
        duel_opponent_guid: Dueling.opponent_guid(character),
        duel_started?: Dueling.active?(character),
        aura_sources: Aura.source_spells(character),
        dispel_options: Aura.dispel_options(character),
        attacker_spell_hit_chance: Aura.attacker_spell_hit_chance(character)
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
    case World.distance_to_guid(character, pet_guid) do
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

  defp notify_defensive_pet(%Character{} = character, attacker_guid) when is_integer(attacker_guid) do
    case Entity.pid(Character.controlled_guid(character)) do
      pid when is_pid(pid) -> send(pid, {:owner_attacked, attacker_guid})
      _ -> :ok
    end
  end

  defp notify_defensive_pet(%Character{}, _attacker_guid), do: :ok

  defp spell_caster_guid(%{caster_guid: guid}) when is_integer(guid), do: guid
  defp spell_caster_guid(guid) when is_integer(guid), do: guid
  defp spell_caster_guid(_caster), do: nil

  defp suspend_pet_for_teleport(%State{character: %Character{unit: %Unit{summon: pet_guid}}} = state)
       when is_integer(pet_guid) and pet_guid > 0 do
    Network.send_packet(Message.SmsgPetSpells.clear())
    State.suspend_active_pet(state)
  end

  defp suspend_pet_for_teleport(%State{} = state), do: state

  @impl GenServer
  def terminate(_reason, %State{character: %Character{}} = state) do
    State.leave_world(state)
    :ok
  end

  def terminate(_reason, _state), do: :ok
end
