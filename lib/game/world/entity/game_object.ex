defmodule ThistleTea.Game.World.Entity.GameObject do
  @moduledoc """
  Owning GenServer for a game object; serves update-object requests, chest
  loot interactions, and reacts to game-event start/stop for event-gated
  spawns.
  """
  use GenServer

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Request, as: ObservationRequest
  alias ThistleTea.Game.Core.AI.CreatureSpell
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.Script.Request, as: ScriptRequest
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Ritual
  alias ThistleTea.Game.Core.Entity.Component.Internal.Summon
  alias ThistleTea.Game.Core.Entity.Component.Internal.Trap
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.GameObject.GameObjectActions
  alias ThistleTea.Game.Core.GameObject.GameObjectInteraction
  alias ThistleTea.Game.Core.GameObject.Goober
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Loot.Actor
  alias ThistleTea.Game.Core.Loot.Commit
  alias ThistleTea.Game.Core.Loot.LootSession
  alias ThistleTea.Game.Core.Loot.Release
  alias ThistleTea.Game.Core.Party
  alias ThistleTea.Game.Core.Pet.SummonEvent
  alias ThistleTea.Game.Core.Profession.Lock
  alias ThistleTea.Game.Core.Profession.Lock.Requirement
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Network.Message.SmsgFishNotHooked
  alias ThistleTea.Game.Network.Message.SmsgGameobjectCustomAnim
  alias ThistleTea.Game.Network.Message.SmsgGameobjectDespawnAnim
  alias ThistleTea.Game.Network.Message.SmsgGameobjectResetState
  alias ThistleTea.Game.Network.Message.SmsgPlayObjectSound
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.AIEnvironment
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Entity.GameObject.Chair
  alias ThistleTea.Game.World.Entity.GameObject.CheerSpeaker
  alias ThistleTea.Game.World.Entity.GameObject.Chest
  alias ThistleTea.Game.World.Entity.GameObject.ElementalRift
  alias ThistleTea.Game.World.Entity.GameObject.Fishing
  alias ThistleTea.Game.World.Entity.GameObject.GhostMagnet
  alias ThistleTea.Game.World.Entity.GameObject.Goober, as: GooberServer
  alias ThistleTea.Game.World.Entity.GameObject.NecroticCamp
  alias ThistleTea.Game.World.Entity.GameObject.OmenLauncher
  alias ThistleTea.Game.World.Entity.GameObject.Ritual, as: RitualServer
  alias ThistleTea.Game.World.Entity.GameObject.SpellCast
  alias ThistleTea.Game.World.Entity.GameObject.Trap, as: TrapServer
  alias ThistleTea.Game.World.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.World.Entity.ScriptDelivery
  alias ThistleTea.Game.World.Entity.ScriptExecution
  alias ThistleTea.Game.World.Loader.Faction, as: FactionLoader
  alias ThistleTea.Game.World.Loader.GameObjectScript, as: GameObjectScriptLoader
  alias ThistleTea.Game.World.Loader.Lock, as: LockLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.System.SpawnPool
  alias ThistleTea.Game.World.Visibility

  require Logger

  @summoning_ritual 18
  @active 0

  def start_link(%GameObject{} = state) do
    GenServer.start_link(__MODULE__, state, name: EntityRegistry.via(state.object.guid))
  end

  @impl GenServer
  def init(%GameObject{} = state) do
    GameEvent.subscribe(state)
    Process.flag(:trap_exit, true)
    state = monitor_owner(state)
    publish_condition_metadata(state)
    World.update_position(state)
    state = Visibility.join_entity(state)
    notify_instance_spawn(state)
    schedule_despawn(state)
    schedule_fishing_bite(state)
    {:ok, state, {:continue, :start_behaviors}}
  end

  @impl GenServer
  def handle_continue(:start_behaviors, %GameObject{} = state) do
    state =
      state
      |> arm_trap()
      |> CheerSpeaker.start()
      |> ElementalRift.start()
      |> GhostMagnet.start()
      |> NecroticCamp.start()
      |> EventSink.emit_pending(Context.new(self()))

    {:noreply, state}
  end

  defp notify_instance_spawn(
         %GameObject{object: %{entry: entry}, internal: %Internal{world: %{instance_id: instance_id} = world}} = state
       )
       when is_integer(instance_id) do
    InstanceSystem.game_object_spawned(world, entry)
    BattlegroundSystem.game_object_spawned(world, state.object.guid, entry)
  end

  defp notify_instance_spawn(_state), do: :ok

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    UpdateObject.from_entity(state)
    |> Outbound.send_packet(pid)

    reset_banner_interaction(state, pid)
    {:noreply, state}
  rescue
    error ->
      Logger.error("Game object update failed: #{Exception.message(error)}")
      {:noreply, state}
  end

  def handle_cast({:battleground_hide_game_object}, state) do
    send(self(), {:script_remove_object, nil})
    {:noreply, state}
  end

  def handle_cast({:set_art_kit, art_kit, animation}, %GameObject{} = state)
      when art_kit in 0..0xFFFFFFFF and animation in 0..0xFFFFFFFF do
    if state.game_object.art_kit == art_kit do
      {:noreply, state}
    else
      state = %{state | game_object: %{state.game_object | art_kit: art_kit}}
      World.broadcast_packet(UpdateObject.from_entity(state, :values), state)

      World.broadcast_packet(
        %SmsgGameobjectCustomAnim{guid: state.object.guid, animation: animation},
        state
      )

      {:noreply, state}
    end
  rescue
    error ->
      Logger.error("Capture banner update failed: #{Exception.message(error)}")
      {:noreply, state}
  end

  def handle_cast({:start_script, steps, target_guid, world}, %GameObject{internal: %{world: world}} = state) do
    handle_cast({:start_script, steps, target_guid}, state)
  end

  def handle_cast({:start_script, _steps, _target_guid, _world}, %GameObject{} = state), do: {:noreply, state}

  def handle_cast({:start_script, steps, target_guid}, %GameObject{} = state)
      when is_list(steps) and is_integer(target_guid) do
    {:noreply, run_script(state, steps, target_guid)}
  rescue
    error ->
      Logger.error("start_script crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  @impl GenServer
  def handle_cast(
        {:gameobject_use, user_guid, _user_level},
        %GameObject{
          internal: %Internal{ritual: %Ritual{} = ritual, world: world} = internal,
          movement_block: %{position: position}
        } = state
      ) do
    {ritual, result} = RitualServer.use(ritual, user_guid, same_group?(ritual.owner_guid, user_guid))
    state = %{state | internal: %{internal | ritual: ritual}}

    if result in [:waiting, :complete] do
      start_ritual_channel(state, ritual, user_guid)
    end

    if result == :complete do
      cast_ritual_completion(state, ritual, world, position)
      cast_ritual_participant_spell(state, ritual)
      release_cooldown(state)
      Entity.finish_game_object_channel(ritual.owner_guid, state.object.guid)
      if not ritual.persistent?, do: send(self(), :despawn)
    end

    {:noreply, state}
  end

  def handle_cast(
        {:ritual_user_left, user_guid},
        %GameObject{internal: %Internal{ritual: %Ritual{} = ritual} = internal} = state
      ) do
    {:noreply, %{state | internal: %{internal | ritual: RitualServer.leave(ritual, user_guid)}}}
  end

  def handle_cast(
        {:gameobject_use, user_guid, user_level},
        %GameObject{internal: %Internal{summon: %Summon{spell_id: spell_id} = summon}} = state
      )
      when is_integer(spell_id) do
    with %Spell{} = spell <- SpellLoader.load(spell_id),
         true <- allowed_user?(summon, user_guid) do
      context = %CastContext{
        caster_guid: summon.owner_guid || user_guid,
        caster_level: user_level,
        target_guid: user_guid,
        spell: spell
      }

      Entity.receive_spell(user_guid, context, spell)
      {:noreply, spend_charge(state)}
    else
      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:gameobject_use, user_guid, _level}, %GameObject{} = state) do
    if GameObjectActions.usable?(state), do: use_object(state, user_guid), else: {:noreply, state}
  rescue
    error ->
      Logger.error("Game object use failed: #{Exception.message(error)}")
      {:noreply, state}
  end

  def handle_cast(
        %Effects.ApplyGameObjectAction{world: world, source_guid: source, spell_id: spell_id, action: action},
        %GameObject{internal: %{world: world}} = state
      ) do
    case World.position(source) do
      {^world, _, _, _} -> {:noreply, state |> activate_by_spell(spell_id, action, source) |> flush_actions()}
      _ -> {:noreply, state}
    end
  rescue
    error ->
      Logger.error("Game object spell action failed: #{Exception.message(error)}")
      {:noreply, state}
  end

  def handle_cast(%Commit{} = command, %GameObject{} = state) do
    {_result, state} = Chest.commit(state, command)
    {:noreply, state}
  end

  def handle_cast(%Release{} = command, %GameObject{} = state) do
    {_result, state} = Chest.release_reservation(state, command)
    {:noreply, state}
  end

  def handle_cast({:operate_game_object, action, reset_delay_ms}, %GameObject{} = state)
      when action in [:open, :close, :reset, :destroy] and is_integer(reset_delay_ms) do
    {:noreply, operate_game_object(state, action, reset_delay_ms)}
  end

  def handle_cast(%SummonEvent{} = event, %GameObject{} = state) do
    state =
      state
      |> ElementalRift.summon_event(event)
      |> GhostMagnet.summon_event(event)
      |> OmenLauncher.summon_event(event)
      |> NecroticCamp.summon_event(event)
      |> EventSink.emit_pending(Context.new(self()))

    {:noreply, state}
  end

  def handle_cast(:firework_launched, %GameObject{} = state) do
    {:noreply, state |> OmenLauncher.firework_launched() |> EventSink.emit_pending(Context.new(self()))}
  end

  @impl GenServer
  def handle_cast(_message, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:release_summon, _from, %GameObject{internal: %{summon: %Summon{}}} = state) do
    {:stop, :normal, cooldown_release(state), state}
  end

  def handle_call(
        {:use_goober, user_guid, world, quest_allowed?},
        _from,
        %GameObject{internal: %{goober: %Internal.Goober{}}} = state
      ) do
    {result, updated} = use_goober(state, user_guid, world, quest_allowed?)
    {:reply, result, flush_actions(updated)}
  rescue
    error ->
      Logger.error("Quest object use failed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:reply, :unavailable, state}
  end

  def handle_call(
        {:loot_view, %Actor{guid: viewer}},
        _from,
        %GameObject{internal: %Internal{fishing: %{owner_guid: owner_guid}}} = state
      )
      when is_integer(owner_guid) and viewer != owner_guid do
    {:reply, {:error, :not_owner}, state}
  end

  def handle_call({:loot_view, %Actor{} = actor}, _from, %GameObject{} = state) do
    {result, state} = Chest.view(state, actor)
    {:reply, result, state}
  end

  def handle_call({:open_lock, %Actor{} = actor, opened, gain?}, {owner_pid, _tag}, %GameObject{} = state) do
    {result, state} = __MODULE__.OpenLock.open(state, actor, opened, gain?, owner_pid: owner_pid)

    state =
      case result do
        {:ok, :disarmed, _gained?} ->
          {:noreply, state} = deplete_trap(state)
          state

        {:ok, _, _} when is_nil(state.internal.goober) ->
          trigger_linked_objects(state, actor.guid)
          state

        _ ->
          state
      end

    {:reply, result, state}
  rescue
    error ->
      Logger.error("Open lock failed: #{Exception.message(error)}")
      {:reply, {:error, :bad_targets}, state}
  end

  def handle_call({:chair_seat, user_map, {user_x, user_y, user_z} = user_position}, _from, %GameObject{} = state) do
    result =
      with {:ok, {seat_x, seat_y, seat_z, _orientation} = position, stand_state} <-
             Chair.seat(state, user_map, user_position),
           true <- Pathfinding.line_of_sight?(user_map, {user_x, user_y, user_z}, {seat_x, seat_y, seat_z}) do
        {:ok, position, stand_state}
      else
        false -> {:error, :line_of_sight}
        error -> error
      end

    {:reply, result, state}
  end

  def handle_call({:fishing_use, owner_guid, skill}, _from, %GameObject{} = state) do
    {result, state} = Fishing.use(state, owner_guid, skill)
    state = publish_condition_metadata(state)
    if match?({:error, reason} when reason in [:not_hooked, :escaped], result), do: send(self(), :despawn)
    {:reply, result, state}
  end

  def handle_call(:fishing_hole_loot, _from, %GameObject{} = state) do
    {result, state} = Fishing.hole_loot(state)

    case result do
      {:ok, _loot, 0} -> send(self(), :fishing_hole_depleted)
      _ -> :ok
    end

    {:reply, result, state}
  end

  def handle_call({:loot_reserve_item, %Actor{} = actor, slot}, {owner_pid, _tag}, %GameObject{} = state) do
    {result, state} = Chest.reserve_item(state, actor, slot, owner_pid)
    {:reply, result, state}
  end

  def handle_call({:loot_validate_commit, %Actor{} = actor, token}, _from, %GameObject{} = state) do
    reply = LootSession.validate_commit(state.internal.loot.session, actor, token)
    {:reply, reply, state}
  end

  def handle_call({:loot_take_gold, %Actor{} = actor}, _from, %GameObject{} = state) do
    {result, state} = Chest.take_gold(state, actor)
    {:reply, result, state}
  end

  def handle_call(
        {:loot_release, %Actor{guid: viewer} = actor},
        _from,
        %GameObject{internal: %Internal{fishing: %{owner_guid: owner_guid}}} = state
      )
      when is_integer(owner_guid) and viewer == owner_guid do
    state = Chest.release(state, actor)
    send(self(), :despawn)
    {:reply, :ok, state}
  end

  def handle_call({:loot_release, %Actor{} = actor}, _from, %GameObject{} = state) do
    state = state |> Chest.release(actor) |> publish_condition_metadata()
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:event_stop, _event}, state) do
    state = state |> CheerSpeaker.stop() |> EventSink.emit_pending(Context.new(self()))

    case SpawnPool.deactivate(state) do
      :pooled -> {:noreply, state}
      :unpooled -> despawn(state)
    end
  end

  def handle_info({:event_start, _event}, state) do
    {:noreply, state}
  end

  def handle_info(
        {:DOWN, token, :process, _pid, _reason},
        %GameObject{internal: %{summon: %Summon{owner_monitor: token}}} = state
      )
      when is_reference(token) do
    despawn(state)
  end

  def handle_info({:DOWN, token, :process, _pid, _reason}, %GameObject{} = state) when is_reference(token) do
    {:noreply, Chest.reservation_lost(state, token)}
  end

  def handle_info({:owner_reaction_changed, _owner_guid}, %GameObject{} = state) do
    Visibility.notify_visibility_changed(state)
    {:noreply, state}
  end

  def handle_info(:despawn, state) do
    despawn(state)
  end

  def handle_info({:script_activate_object, user_guid}, %GameObject{internal: %Internal{trap: %Trap{} = trap}} = state)
      when is_integer(user_guid) do
    activate_trap(state, trap, user_guid)
  end

  def handle_info({:script_activate_object, user_guid}, %GameObject{game_object: %{type_id: type}} = state)
      when type in [0, 1], do: use_object(state, user_guid)

  def handle_info({:script_activate_object, user_guid}, %GameObject{internal: %{goober: %Internal.Goober{}}} = state) do
    if Guid.entity_type(user_guid) == :player do
      Entity.use_quest_object(user_guid, state.object.guid, state.internal.world)
      {:noreply, state}
    else
      {_result, state} = use_goober(state, user_guid, state.internal.world, true)
      {:noreply, flush_actions(state)}
    end
  rescue
    error ->
      Logger.error("Scripted goober use failed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_info({:script_activate_object, _user_guid}, %GameObject{} = state) do
    next = if state.game_object.state == 0, do: 1, else: 0
    {:noreply, state |> GameObjectActions.set_state(next) |> flush_actions()}
  end

  def handle_info({:script_remove_object, respawn_delay_ms}, %GameObject{} = state) do
    case SpawnPool.suspend(state, respawn_delay_ms) do
      :pooled ->
        {:noreply, state}

      :unpooled ->
        despawn(state)
    end
  end

  def handle_info({:script_operate_game_object, action, reset_delay_ms}, %GameObject{} = state)
      when action in [:open, :close, :reset] and is_integer(reset_delay_ms) do
    {:noreply, operate_game_object(state, action, reset_delay_ms)}
  end

  def handle_info({:restore_game_object, revision, previous}, %GameObject{} = state),
    do: {:noreply, state |> GameObjectActions.restore(revision, previous) |> flush_actions()}

  def handle_info({:finish_game_object_use, revision}, %GameObject{} = state),
    do: {:noreply, state |> Goober.finish(revision) |> flush_actions()}

  def handle_info({:game_object_spell, %Spell{} = spell, user_guid}, %GameObject{} = state) do
    {:noreply, state |> GooberServer.finish_spell(spell, user_guid) |> flush_actions()}
  rescue
    error ->
      Logger.error("Quest object spell failed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_info({:scripted_cast, %CreatureSpell{spell_id: spell_id}, target_guid}, %GameObject{} = state) do
    case SpellLoader.cached(spell_id) do
      %Spell{} = spell -> {:noreply, state |> GooberServer.finish_spell(spell, target_guid) |> flush_actions()}
      _missing -> {:noreply, state}
    end
  rescue
    error ->
      Logger.error("Scripted object cast failed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_info({:script_command, %ScriptRequest{} = request}, %GameObject{} = state) do
    state = state |> ScriptExecution.command(request) |> EventSink.emit_pending() |> broadcast_if_pending()
    {:noreply, state}
  rescue
    error ->
      Logger.error("script command crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      ScriptDelivery.reply(request, :failed)
      {:noreply, state}
  end

  def handle_info({:script_resume, id, receipt, world, result}, %GameObject{} = state) do
    state =
      state |> ScriptExecution.resume(id, receipt, world, result) |> EventSink.emit_pending() |> broadcast_if_pending()

    {:noreply, state}
  rescue
    error ->
      Logger.error("script resume crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_info({:ai_script_steps, steps, target_guid, world}, %GameObject{internal: %{world: world}} = state) do
    handle_info({:ai_script_steps, steps, target_guid}, state)
  end

  def handle_info({:ai_script_steps, _steps, _target_guid, _world}, %GameObject{} = state), do: {:noreply, state}

  def handle_info({:ai_script_steps, steps, target_guid}, %GameObject{} = state)
      when is_list(steps) and is_integer(target_guid) do
    {:noreply, run_script(state, steps, target_guid)}
  rescue
    error ->
      Logger.error("ai_script_steps crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_info(:trap_tick, %GameObject{internal: %Internal{trap: %Trap{} = trap}} = state) do
    case TrapServer.target(state) do
      target_guid when is_integer(target_guid) ->
        activate_trap(state, trap, target_guid)

      _ ->
        Process.send_after(self(), :trap_tick, 200)
        {:noreply, state}
    end
  end

  def handle_info(:fishing_bite, %GameObject{} = state) do
    state = state |> Fishing.bite() |> publish_condition_metadata()
    UpdateObject.from_entity(state, :values) |> World.broadcast_packet(state)

    %SmsgGameobjectCustomAnim{guid: state.object.guid}
    |> World.broadcast_packet(state)

    %SmsgPlayObjectSound{sound_id: 3355, guid: state.object.guid}
    |> World.broadcast_packet(state)

    {:noreply, state}
  end

  def handle_info(:fishing_expire, %GameObject{internal: %Internal{fishing: %{consumed?: true}}} = state) do
    {:noreply, state}
  end

  def handle_info(:fishing_expire, %GameObject{internal: %Internal{fishing: fishing}} = state) do
    Outbound.send_packet(%SmsgFishNotHooked{}, fishing.owner_guid)
    despawn(state)
  end

  def handle_info(:fishing_hole_depleted, %GameObject{} = state) do
    case SpawnPool.recycle(state) do
      :pooled -> {:noreply, state}
      :unpooled -> {:noreply, state |> Fishing.deplete() |> publish_condition_metadata(false)}
    end
  end

  def handle_info(:fishing_hole_respawn, %GameObject{} = state) do
    {:noreply, state |> Fishing.respawn() |> publish_condition_metadata()}
  end

  def handle_info(:launch_firework, %GameObject{} = state) do
    {:noreply, state |> CheerSpeaker.launch() |> EventSink.emit_pending(Context.new(self()))}
  end

  def handle_info(:rift_upkeep, %GameObject{} = state) do
    {:noreply, state |> ElementalRift.upkeep() |> EventSink.emit_pending(Context.new(self()))}
  end

  def handle_info(:ghost_magnet_call, %GameObject{} = state) do
    {:noreply, state |> GhostMagnet.call() |> EventSink.emit_pending(Context.new(self()))}
  end

  def handle_info(:ghost_magnet_replace, %GameObject{} = state) do
    {:noreply, state |> GhostMagnet.replace() |> EventSink.emit_pending(Context.new(self()))}
  end

  def handle_info(:camp_raise, %GameObject{} = state) do
    {:noreply, state |> NecroticCamp.raise_shard() |> EventSink.emit_pending(Context.new(self()))}
  end

  def handle_info(:camp_upkeep, %GameObject{} = state) do
    {:noreply, state |> NecroticCamp.upkeep() |> EventSink.emit_pending(Context.new(self()))}
  end

  def handle_info(:camp_buttress, %GameObject{} = state) do
    {:noreply, state |> NecroticCamp.buttress() |> EventSink.emit_pending(Context.new(self()))}
  end

  def handle_info(:chest_respawn, %GameObject{} = state) do
    case SpawnPool.recycle(state) do
      :pooled -> {:noreply, state}
      :unpooled -> {:noreply, state |> Chest.respawn() |> publish_condition_metadata()}
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    release_cooldown(state)
    finish_ritual_channels(state)
    stop_linked_objects(state)
    World.remove_position(state)
    Visibility.leave_entity(state)
    Metadata.delete(state.object.guid)
  end

  defp release_cooldown(
         %GameObject{internal: %{summon: %Summon{cooldown_event: %Effects.ActivateCooldown{} = event} = summon}} = state
       ) do
    case summon.owner_pid || Entity.pid(event.target_guid) do
      pid when is_pid(pid) -> send(pid, cooldown_release(state))
      _ -> :ok
    end
  end

  defp release_cooldown(_state), do: :ok

  defp cooldown_release(
         %GameObject{internal: %{summon: %Summon{cooldown_event: %Effects.ActivateCooldown{} = event}}} = state
       ) do
    %{event | cancel?: match?(%Ritual{completed?: false}, state.internal.ritual)}
  end

  defp cooldown_release(_state), do: nil

  defp despawn(state) do
    send_despawn_animation(state)
    pid = self()

    Task.start(fn ->
      World.stop_entity(pid)
    end)

    {:noreply, state}
  end

  defp send_despawn_animation(
         %GameObject{internal: %Internal{summon: %Summon{}}, game_object: %{type_id: type, state: go_state}} = state
       )
       when type != @summoning_ritual or go_state == @active do
    World.broadcast_packet(%SmsgGameobjectDespawnAnim{guid: state.object.guid}, state)
  end

  defp send_despawn_animation(_state), do: :ok

  defp schedule_despawn(%GameObject{internal: %Internal{fishing: %{bite_delay_ms: delay}}})
       when is_integer(delay) and delay > 0 do
    nil
  end

  defp schedule_despawn(%GameObject{internal: %Internal{summon: %Summon{despawn_in_ms: despawn_in_ms}}})
       when is_integer(despawn_in_ms) and despawn_in_ms > 0 do
    Process.send_after(self(), :despawn, despawn_in_ms)
  end

  defp schedule_despawn(_state), do: nil

  defp monitor_owner(%GameObject{internal: %{summon: %Summon{owner_pid: pid} = summon}} = state) when is_pid(pid) do
    summon = %{summon | owner_monitor: Process.monitor(pid)}
    %{state | internal: %{state.internal | summon: summon}}
  end

  defp monitor_owner(state), do: state

  defp stop_linked_objects(%GameObject{internal: %{summon: %Summon{linked_guids: guids}}}) do
    Enum.each(guids, fn guid ->
      case Entity.pid(guid) do
        pid when is_pid(pid) -> send(pid, :despawn)
        _missing -> :ok
      end
    end)
  end

  defp stop_linked_objects(%GameObject{}), do: :ok

  defp use_goober(%GameObject{} = state, user_guid, world, quest_allowed?) do
    {result, updated} = GooberServer.use(state, user_guid, world, quest_allowed?, Time.now())

    if result == :activated do
      trigger_linked_objects(updated, user_guid)
      GooberServer.start_script(updated, user_guid)
      {result, GooberServer.start_spell(updated, user_guid)}
    else
      {result, updated}
    end
  end

  defp trigger_linked_objects(%GameObject{internal: %{summon: %Summon{linked_guids: [_ | _] = guids}}}, user_guid) do
    Enum.each(guids, fn guid ->
      case Entity.pid(guid) do
        pid when is_pid(pid) -> send(pid, {:script_activate_object, user_guid})
        _missing -> :ok
      end
    end)
  end

  defp trigger_linked_objects(%GameObject{} = state, user_guid) do
    with guid when is_integer(guid) <- TrapServer.linked_guid(state),
         pid when is_pid(pid) <- Entity.pid(guid) do
      send(pid, {:script_activate_object, user_guid})
    end
  end

  defp schedule_fishing_bite(%GameObject{internal: %Internal{fishing: %{bite_delay_ms: delay}}})
       when is_integer(delay) and delay > 0 do
    Process.send_after(self(), :fishing_bite, delay)
    Process.send_after(self(), :fishing_expire, delay + 5_000)
  end

  defp schedule_fishing_bite(_state), do: nil

  defp arm_trap(%GameObject{internal: %Internal{trap: %Trap{start_delay_ms: delay} = trap}} = state) do
    TrapServer.publish_range(state)
    if trap.radius > 0, do: Process.send_after(self(), :trap_tick, max(delay, 200))
    trap = %{trap | ready_at: Time.now() + delay}
    %{state | internal: %{state.internal | trap: trap}}
  end

  defp arm_trap(state), do: state

  defp run_script(%GameObject{} = state, steps, target_guid) do
    now = Time.now()

    request = ObservationRequest.for_script(steps, [target_guid])

    context = AIEnvironment.context(state, now, request)
    {state, _blackboard} = Script.run(state, Blackboard.new(), steps, target_guid, context)
    state |> EventSink.emit_pending() |> broadcast_if_pending()
  end

  defp activate_by_spell(%GameObject{} = state, spell_id, action, caster_guid) when is_integer(spell_id) do
    case GameObjectScriptLoader.activated(state.object.entry, spell_id, state.movement_block.position) do
      {:claim, steps, claimed_action} ->
        Entity.start_script(caster_guid, steps, caster_guid)
        GameObjectActions.apply(state, claimed_action, caster_guid)

      :pass ->
        GameObjectActions.apply(state, action, caster_guid)
    end
  end

  defp activate_by_spell(%GameObject{} = state, _spell_id, action, caster_guid),
    do: GameObjectActions.apply(state, action, caster_guid)

  defp operate_game_object(%GameObject{} = state, action, reset_delay_ms) do
    state |> GameObjectActions.operate(action, reset_delay_ms) |> flush_actions()
  end

  defp flush_actions(%GameObject{} = state) do
    state
    |> EventSink.emit_pending(Context.new(self()))
    |> publish_condition_metadata()
    |> broadcast_if_pending()
  end

  defp use_object(%GameObject{internal: %{trap: %Trap{} = trap}} = state, user_guid),
    do: activate_trap(state, trap, user_guid)

  defp use_object(%GameObject{game_object: %{type_id: type}} = state, user_guid) when type in [0, 1] do
    trigger_linked_objects(state, user_guid)
    ported = GameObjectScriptLoader.ported(state.object.entry, state.movement_block.position)
    Entity.start_script(user_guid, ported ++ GameObjectScriptLoader.get(GameObject.db_guid(state)), state.object.guid)
    {:noreply, state |> GameObjectActions.activate() |> flush_actions()}
  end

  defp use_object(%GameObject{} = state, _user_guid), do: {:noreply, state}

  defp cast_ritual_completion(state, %Ritual{} = ritual, world, {x, y, z, orientation}) do
    with spell_id when is_integer(spell_id) <- ritual.completion_spell_id,
         %Spell{} = spell <- SpellLoader.load(spell_id) do
      context = %CastContext{
        caster_guid: ritual.owner_guid,
        caster_level: state.game_object.level || 1,
        caster_position: {world, x, y, z},
        caster_orientation: orientation,
        caster_zone: ritual.zone_id,
        target_guid: ritual.target_guid,
        selected_target_guid: ritual.target_guid,
        spell: spell
      }

      Entity.receive_spell(ritual.owner_guid, context, spell)
    end
  end

  defp cast_ritual_participant_spell(state, %Ritual{} = ritual) do
    with spell_id when is_integer(spell_id) <- ritual.caster_target_spell_id,
         target_guid when is_integer(target_guid) <- Enum.random(ritual.users),
         %Spell{} = spell <- SpellLoader.load(spell_id) do
      context = %CastContext{
        caster_guid: target_guid,
        caster_level: state.game_object.level || 1,
        target_guid: target_guid,
        selected_target_guid: target_guid,
        spell: spell
      }

      Entity.receive_spell(target_guid, context, spell)
    end
  end

  defp start_ritual_channel(state, %Ritual{} = ritual, user_guid) do
    with spell_id when is_integer(spell_id) <- ritual.animation_spell_id,
         %Spell{} = spell <- SpellLoader.load(spell_id) do
      duration_ms = state.internal.summon.despawn_in_ms || spell.duration_ms || 0
      Entity.start_game_object_channel(user_guid, state.object.guid, spell, duration_ms)
    end
  end

  defp finish_ritual_channels(%GameObject{object: %{guid: guid}, internal: %Internal{ritual: %Ritual{} = ritual}}) do
    Enum.each(ritual.users, &Entity.finish_game_object_channel(&1, guid))
  end

  defp finish_ritual_channels(%GameObject{}), do: nil

  defp trigger_trap(state, %Trap{owner_guid: owner_guid, spell_id: spell_id, level: template_level}, target_guid) do
    case SpellLoader.cached(spell_id) do
      %Spell{} = spell ->
        level = Enum.find([template_level, state.game_object.level, 60], &(is_integer(&1) and &1 > 0))
        caster = trap_caster(state, owner_guid, level)

        state =
          state
          |> SpellCast.launch(immediate_trap_spell(spell), target_guid,
            caster_guid: owner_guid || state.object.guid,
            level: level
          )
          |> EventSink.emit_pending(Context.new(self()))

        spawn_trap_areas(caster, spell)
        state

      _ ->
        state
    end
  end

  defp activate_trap(state, trap, target_guid) do
    now = Time.now()

    if TrapServer.ready?(trap, now) do
      do_activate_trap(state, trap, target_guid, now)
    else
      {:noreply, state}
    end
  end

  defp do_activate_trap(state, trap, target_guid, now) do
    state = trigger_trap(state, trap, target_guid)

    case TrapServer.consume(trap) do
      :depleted ->
        deplete_trap(state)

      %Trap{} = remaining ->
        if remaining.radius > 0, do: Process.send_after(self(), :trap_tick, remaining.cooldown_ms)
        remaining = %{remaining | ready_at: now + remaining.cooldown_ms}
        {:noreply, %{state | internal: %{state.internal | trap: remaining}}}
    end
  end

  defp deplete_trap(%GameObject{internal: %{trap: %Trap{} = trap}} = state) do
    state = %{state | internal: %{state.internal | trap: %{trap | depleted?: true}}}

    result =
      case state.internal.spawn do
        %Internal.Spawn{respawn_delay_ms: delay} when is_integer(delay) and delay > 0 -> SpawnPool.suspend(state, delay)
        _ -> SpawnPool.recycle(state)
      end

    case result do
      :pooled -> {:noreply, state}
      :unpooled -> despawn(state)
    end
  end

  defp trap_caster(state, owner_guid, level) do
    %{
      object: %{guid: owner_guid || state.object.guid},
      unit: %Unit{level: level},
      internal: %Internal{world: state.internal.world},
      movement_block: state.movement_block
    }
  end

  defp immediate_trap_spell(%Spell{} = spell) do
    %{spell | effects: Enum.reject(spell.effects, &(&1.type == :persistent_area_aura))}
  end

  defp spawn_trap_areas(caster, %Spell{} = spell) do
    {x, y, z, _o} = caster.movement_block.position

    Enum.each(spell.effects, fn
      %{type: :persistent_area_aura} = effect ->
        event = Effects.spawn_area_effect(spell, effect, {x, y, z}, spell.duration_ms || 0)
        EventSink.emit(caster, event)

      _effect ->
        nil
    end)
  end

  defp spend_charge(%GameObject{internal: %Internal{summon: %Summon{charges: charges} = summon} = internal} = state)
       when is_integer(charges) do
    if charges > 1 do
      %{state | internal: %{internal | summon: %{summon | charges: charges - 1}}}
    else
      send(self(), :despawn)
      %{state | internal: %{internal | summon: %{summon | charges: 0, spell_id: nil}}}
    end
  end

  defp spend_charge(state), do: state

  defp reset_banner_interaction(%GameObject{internal: %{gathering: %{lock_id: lock_id}}} = state, pid) do
    case LockLoader.get(lock_id) do
      %Lock{requirements: requirements} ->
        if Enum.any?(requirements, &match?(%Requirement{type: :skill, index: 17}, &1)) do
          Outbound.send_packet(%SmsgGameobjectResetState{guid: state.object.guid}, pid)
        end

      _missing ->
        :ok
    end
  end

  defp reset_banner_interaction(%GameObject{}, _pid), do: :ok

  defp broadcast_if_pending(%GameObject{internal: %Internal{broadcast_update?: true} = internal} = state) do
    publish_condition_metadata(state)
    UpdateObject.from_entity(state, :values) |> World.broadcast_packet(state)
    %{state | internal: %{internal | broadcast_update?: false}}
  end

  defp broadcast_if_pending(%GameObject{} = state), do: state

  defp publish_condition_metadata(%GameObject{} = state, spawned? \\ true) do
    metadata =
      Map.merge(FactionLoader.metadata(state.game_object.faction), %{
        db_guid: GameObject.db_guid(state),
        go_spawned?: spawned?,
        go_state: state.game_object.state,
        owner_guid: state.game_object.created_by,
        go_trap_stealthed?: match?(%Trap{stealthed?: true}, state.internal.trap),
        go_lock_override: state.internal.object_action.lock_override
      })

    Metadata.update(state.object.guid, metadata)

    if is_nil(state.internal.loot) and is_nil(state.internal.fishing),
      do: Metadata.update(state.object.guid, %{loot_state: if(state.internal.object_action.active?, do: 2, else: 1)})

    publish_geometry(state)
  end

  defp publish_geometry(%GameObject{} = state) do
    object = state.game_object
    rotation = {object.rotation0 || 0.0, object.rotation1 || 0.0, object.rotation2 || 0.0, object.rotation3 || 0.0}

    Metadata.update(state.object.guid, %{
      go_type: state.game_object.type_id,
      go_flags: state.game_object.flags,
      go_scale: state.object.scale_x,
      go_rotation: GameObjectInteraction.rotation(rotation, object.facing || 0.0)
    })

    state
  end

  defp allowed_user?(%Summon{party_only?: true, owner_guid: owner_guid}, user_guid) when is_integer(owner_guid) do
    user_guid == owner_guid or same_group?(owner_guid, user_guid)
  end

  defp allowed_user?(_summon, _user_guid), do: true

  defp same_group?(owner_guid, user_guid) do
    case {PartySystem.group_of(owner_guid), PartySystem.group_of(user_guid)} do
      {%Party.Group{id: id}, %Party.Group{id: id}} -> true
      _ -> false
    end
  end
end
