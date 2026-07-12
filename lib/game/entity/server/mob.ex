defmodule ThistleTea.Game.Entity.Server.Mob do
  @moduledoc """
  Owning GenServer for a mob: ticks its behavior tree and applies incoming
  attacks and spells through the pure core. The post-death lifecycle is
  delegated — the corpse phase (loot, rolls, decay, removal) to `Mob.Corpse`
  and the respawn state machine to `Mob.Respawn`.
  """
  use GenServer

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells, as: MobSpells
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet, as: PetBT
  alias ThistleTea.Game.Entity.Logic.AI.EventAI
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Entity.Server.Mob.Corpse
  alias ThistleTea.Game.Entity.Server.Mob.Respawn
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ChaseWatch
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.Visibility

  require Logger

  @ai_tick_retry_ms 1_000
  @dynamic_flag_tapped 0x0004
  @summon_despawn_retry_ms 10_000
  @ooc_gated_despawn_types [1, 2, 4]

  def start_link(%Mob{} = state) do
    GenServer.start_link(__MODULE__, state, name: EntityRegistry.via(state.object.guid))
  end

  @impl GenServer
  def init(%Mob{} = state) do
    GameEvent.subscribe(state)
    Process.flag(:trap_exit, true)
    state = BT.init(state, behavior_tree(state))
    World.update_position(state)
    state = Visibility.join_entity(state)

    state =
      state
      |> EventAI.with_blackboard(&EventAI.on_spawned(&1, &2, Time.now()))
      |> EventSink.emit_pending()

    state =
      state
      |> schedule_summon_despawn()
      |> schedule_ai_tick(0)

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    if Corpse.removed?(state) do
      {:noreply, state}
    else
      now = Time.now()
      state = Movement.sync_position(state, now)
      World.update_position(state)
      state = Visibility.refresh_entity(state)

      Core.update_object(state)
      |> Network.send_packet(pid)

      send_resume_move(state, pid, now)

      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast({:move_to, x, y, z}, state) do
    state = Movement.move_to(state, {x, y, z}, [], Time.now())
    state = EventSink.emit_pending(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:aggro_probe, target}, %Mob{internal: %Internal{in_combat: false}} = state)
      when is_integer(target) do
    state
    |> mark_aggro_ready()
    |> cancel_ai_tick()
    |> run_ai_tick()
  end

  def handle_cast({:aggro_probe, _target}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:receive_spell, caster, spell}, state) do
    caster_guid = caster_guid(caster)

    state =
      if Spell.harmful?(spell) do
        state
        |> engage_combat(caster_guid)
        |> eventai_spell_hit(caster_guid, spell)
      else
        state
      end

    {state, events} = SpellEffect.receive(state, caster, spell, Time.now())

    state =
      state
      |> EventSink.emit(events)
      |> wake_ai_tick()

    {:noreply, state, {:continue, :maybe_broadcast}}
  end

  def handle_cast({:remove_aura, spell_id, caster_guid}, state) do
    {state, events} = Aura.remove_source_spell(state, spell_id, caster_guid, Time.now())
    state = EventSink.emit(state, events)
    {:noreply, wake_ai_tick(state), {:continue, :maybe_broadcast}}
  end

  @impl GenServer
  def handle_cast({:receive_heal, amount}, state) do
    state = Core.heal(state, amount)
    {:noreply, state, {:continue, :maybe_broadcast}}
  end

  @impl GenServer
  def handle_cast({:heal_threat, healer_guid, healed_guid, amount}, %Mob{internal: %Internal{in_combat: true}} = state)
      when is_integer(healer_guid) and is_number(amount) and amount > 0 do
    if Threat.tracking?(state, healed_guid) and Hostility.valid_hostile_target?(state, healer_guid) do
      state =
        state
        |> Threat.add(healer_guid, amount / attacker_count(healed_guid))
        |> wake_ai_tick()

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:heal_threat, _healer_guid, _healed_guid, _amount}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:drop_threat, source_guid}, %Mob{} = state) do
    state = state |> MobBT.drop_threat(source_guid) |> EventSink.emit_pending() |> wake_ai_tick()
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:loot_roll_vote, voter_guid, slot, vote}, %Mob{} = state) do
    {:noreply, Corpse.roll_vote(state, voter_guid, slot, vote)}
  end

  @impl GenServer
  def handle_cast({:receive_attack, %{caster: caster} = attack}, state) do
    state = engage_combat(state, caster)

    {state, events} = Combat.receive_attack(state, attack, Time.now())

    state =
      state
      |> EventSink.emit(events)
      |> wake_ai_tick()

    {:noreply, state, {:continue, :maybe_broadcast}}
  end

  @impl GenServer
  def handle_call(:threat_table, _from, %Mob{} = state) do
    {:reply, {:ok, %{victim: state.unit.target, entries: Threat.entries(state)}}, state}
  end

  def handle_call({:loot_view, viewer}, _from, %Mob{} = state) do
    {result, state} = Corpse.view(state, viewer)
    {:reply, result, state}
  end

  def handle_call({:loot_master_give, giver, slot, target}, _from, %Mob{} = state) do
    {result, state} = Corpse.master_give(state, giver, slot, target)
    {:reply, result, state}
  end

  def handle_call({:loot_take_item, slot}, _from, %Mob{} = state) do
    {result, state} = Corpse.take_item(state, slot)
    {:reply, result, state}
  end

  def handle_call({:loot_return_item, slot}, _from, %Mob{} = state) do
    {:reply, :ok, Corpse.return_item(state, slot)}
  end

  def handle_call(:loot_take_gold, _from, %Mob{} = state) do
    {result, state} = Corpse.take_gold(state)
    {:reply, result, state}
  end

  def handle_call({:loot_release, viewer}, _from, %Mob{} = state) do
    {:reply, :ok, Corpse.release(state, viewer)}
  end

  @impl GenServer
  def handle_info({:loot_roll_timeout, slot}, %Mob{} = state) do
    {:noreply, Corpse.roll_timeout(state, slot)}
  end

  @impl GenServer
  def handle_info({:remove_corpse, token}, %Mob{} = state) do
    {:noreply, Corpse.remove(state, token)}
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

  @impl GenServer
  def handle_info({:ai_tick, token}, %{internal: %Internal{ai_tick_token: token}} = state) when is_reference(token) do
    state
    |> clear_ai_tick_ref()
    |> run_ai_tick()
  end

  def handle_info({:ai_tick, _token}, state) do
    {:noreply, state}
  end

  def handle_info(:ai_tick, state) do
    state
    |> cancel_ai_tick()
    |> run_ai_tick()
  end

  def handle_info({:target_moved, target}, %Mob{unit: %Unit{target: target}} = state) when is_integer(target) do
    state
    |> mark_chase_ready()
    |> cancel_ai_tick()
    |> run_ai_tick()
  end

  def handle_info({:target_moved, _target}, state) do
    {:noreply, sync_chase_watch(state)}
  end

  def handle_info(:respawn, %Mob{} = state) do
    {:noreply, Respawn.handle(state)}
  end

  def handle_info({:ai_script_steps, steps, target_guid}, %Mob{} = state) do
    if Corpse.removed?(state) do
      {:noreply, state}
    else
      state =
        state
        |> EventAI.with_blackboard(&Script.execute_steps(&1, &2, steps, target_guid, Time.now()))
        |> EventSink.emit_pending()

      {:noreply, state, {:continue, :maybe_broadcast}}
    end
  rescue
    error ->
      Logger.error("ai_script_steps crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  def handle_info({:force_attack, target_guid}, %Mob{} = state) when is_integer(target_guid) do
    if Core.dead?(state) or Corpse.removed?(state) do
      {:noreply, state}
    else
      state =
        state
        |> engage_combat(target_guid)
        |> wake_ai_tick()

      {:noreply, state, {:continue, :maybe_broadcast}}
    end
  end

  def handle_info({:pet_command, :dismiss, _target_guid}, %Mob{internal: %Internal{pet: %Pet{}}} = state) do
    {:noreply, Respawn.despawn(state, nil)}
  end

  def handle_info({:pet_command, command, target_guid}, %Mob{internal: %Internal{pet: %Pet{}}} = state) do
    state = state |> PetBT.command(command, target_guid) |> wake_ai_tick()
    {:noreply, state, {:continue, :maybe_broadcast}}
  end

  def handle_info({:pet_reaction, reaction}, %Mob{internal: %Internal{pet: %Pet{}}} = state) do
    state = state |> PetBT.reaction(reaction) |> wake_ai_tick()
    {:noreply, state}
  end

  def handle_info({:pet_set_actions, actions}, %Mob{internal: %Internal{pet: %Pet{}}} = state) do
    state = PetBT.set_actions(state, actions)
    blackboard = %{Blackboard.from_any(state.internal.blackboard) | spell_timers: nil, next_spell_list_at: 0}
    state = %{state | internal: %{state.internal | blackboard: blackboard}} |> wake_ai_tick()
    {:noreply, state}
  end

  def handle_info({:owner_attacked, attacker_guid}, %Mob{internal: %Internal{pet: %Pet{}}} = state)
      when is_integer(attacker_guid) do
    state = state |> engage_combat(attacker_guid) |> wake_ai_tick()
    {:noreply, state, {:continue, :maybe_broadcast}}
  end

  def handle_info(
        {:pet_cast, spell_id, target_guid},
        %Mob{internal: %Internal{pet: %Pet{}, spellbook: spellbook}} = state
      )
      when is_integer(spell_id) do
    known? = Map.has_key?(spellbook, spell_id)

    state =
      with true <- known?,
           %Spell{} = spell <- SpellLoader.load(spell_id),
           true <- valid_pet_spell_target?(state, spell, target_guid) do
        target_guid = if is_integer(target_guid) and target_guid > 0, do: target_guid, else: state.object.guid
        blackboard = Blackboard.from_any(state.internal.blackboard)
        entry = %CreatureSpell{spell_id: spell_id, cast_target: if(Spell.harmful?(spell), do: :victim, else: :self)}
        {state, blackboard} = MobSpells.attempt_scripted_cast(state, blackboard, entry, target_guid, Time.now())
        %{state | internal: %{state.internal | blackboard: blackboard}}
      else
        _ -> state
      end

    {:noreply, wake_ai_tick(state), {:continue, :maybe_broadcast}}
  end

  def handle_info(:summon_despawn, %Mob{} = state) do
    if state.internal.in_combat and ooc_gated_despawn?(state) do
      Process.send_after(self(), :summon_despawn, @summon_despawn_retry_ms)
      {:noreply, state}
    else
      {:noreply, Respawn.despawn(state, nil)}
    end
  end

  def handle_info({:despawn_creature, respawn_delay_ms}, %Mob{} = state) do
    {:noreply, Respawn.despawn(state, respawn_delay_ms)}
  end

  def handle_info(:pet_stop, %Mob{internal: %Internal{pet: %Pet{}}} = state) do
    pid = self()
    Task.start(fn -> World.stop_entity(pid) end)
    {:noreply, state}
  end

  def handle_info({:event_stop, _event}, state) do
    case SpawnPool.deactivate(state) do
      :pooled -> {:noreply, state}
      :unpooled -> stop_after_event(state)
    end
  end

  def handle_info({:event_start, _event}, state) do
    {:noreply, state}
  end

  defp stop_after_event(state) do
    pid = self()
    Task.start(fn -> World.stop_entity(pid) end)
    {:noreply, state}
  end

  defp run_ai_tick(%{internal: %Internal{behavior_tree: behavior_tree}} = state) do
    if Corpse.removed?(state) do
      {:noreply, unwatch_chase(state)}
    else
      state = Movement.sync_position(state, Time.now())
      World.update_position(state)
      state = Visibility.refresh_entity(state)
      started_at = System.monotonic_time()
      {status, state} = BT.tick(behavior_tree, state)
      duration = System.monotonic_time() - started_at
      state = EventSink.emit_pending(state)
      state = sync_chase_watch(state)
      emit_ai_tick_telemetry(state, status, duration)
      state = schedule_next_ai_tick(state, status)
      {:noreply, state, {:continue, :maybe_broadcast}}
    end
  rescue
    error ->
      Logger.error("Mob AI tick crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      state = schedule_ai_tick(state, @ai_tick_retry_ms)
      {:noreply, state}
  end

  @impl GenServer
  def handle_continue(:maybe_broadcast, %Mob{} = state) do
    state =
      state
      |> maybe_finalize_death()
      |> broadcast_if_pending()

    {:noreply, state}
  end

  defp broadcast_if_pending(%Mob{internal: %Internal{broadcast_update?: true}} = state) do
    if !Corpse.removed?(state) do
      update_type = if Core.dead?(state), do: :create_object2, else: :values
      Core.update_object(state, update_type) |> World.broadcast_packet(state)

      Metadata.update(state.object.guid, %{
        alive?: not Core.dead?(state),
        health_pct: Core.health_pct(state),
        unit_flags: state.unit.flags,
        orientation: elem(state.movement_block.position, 3),
        aura_sources: Aura.source_spells(state)
      })
    end

    %{state | internal: %{state.internal | broadcast_update?: false}}
  end

  defp broadcast_if_pending(%Mob{} = state), do: state

  @impl GenServer
  def terminate(_reason, state) do
    notify_pet_owner_removed(state)
    release_victim(state)
    unwatch_chase(state)
    World.remove_position(state)
    Visibility.leave_entity(state)
    Metadata.delete(state.object.guid)
  end

  defp behavior_tree(%Mob{internal: %Internal{pet: %Pet{}}}), do: PetBT.tree()
  defp behavior_tree(%Mob{}), do: MobBT.tree()

  defp notify_pet_owner_removed(%Mob{object: %{guid: guid}, internal: %Internal{pet: %Pet{owner_guid: owner_guid}}}) do
    case Entity.pid(owner_guid) do
      pid when is_pid(pid) -> send(pid, {:pet_removed, guid})
      _ -> :ok
    end
  end

  defp notify_pet_owner_removed(%Mob{}), do: :ok

  defp schedule_summon_despawn(
         %Mob{internal: %Internal{spawn: %Spawn{temporary?: true, despawn_delay_ms: delay}}} = state
       )
       when is_integer(delay) and delay > 0 do
    Process.send_after(self(), :summon_despawn, delay)
    state
  end

  defp schedule_summon_despawn(%Mob{} = state), do: state

  defp ooc_gated_despawn?(%Mob{internal: %Internal{spawn: %Spawn{despawn_type: despawn_type}}}) do
    despawn_type in @ooc_gated_despawn_types
  end

  defp ooc_gated_despawn?(%Mob{}), do: false

  defp release_victim(%Mob{internal: %Internal{in_combat: true}, unit: %Unit{target: target}})
       when is_integer(target) and target > 0 do
    Metadata.decrement(target, :attacker_count, 0)
  end

  defp release_victim(_state), do: :ok

  defp wake_ai_tick(%Mob{} = state) do
    if Core.dead?(state), do: deactivate_ai(state), else: schedule_ai_tick(state, 0)
  end

  defp schedule_next_ai_tick(%Mob{} = state, status) do
    if Core.dead?(state), do: deactivate_ai(state), else: schedule_ai_tick(state, Tick.mob_delay(status))
  end

  defp emit_ai_tick_telemetry(%Mob{object: %{guid: guid}}, status, duration) do
    :telemetry.execute(
      [:thistle_tea, :mob, :ai_tick],
      %{duration: duration, next_delay_ms: Tick.mob_delay(status)},
      %{guid: guid, status: tick_status(status), wake_reason: wake_reason(status)}
    )
  end

  defp tick_status({:running, _delay}), do: :running
  defp tick_status({:running, _delay, _reason}), do: :running
  defp tick_status(status) when is_atom(status), do: status
  defp tick_status(_status), do: :unknown

  defp wake_reason({:running, _delay, reason}) when is_atom(reason), do: reason
  defp wake_reason({:running, _delay}), do: :unspecified
  defp wake_reason(:running), do: :unspecified
  defp wake_reason(status) when is_atom(status), do: status
  defp wake_reason(_status), do: :unknown

  defp send_resume_move(%Mob{} = state, pid, now) do
    case Movement.resume_spline(state, now) do
      nil ->
        :ok

      resumed ->
        resumed
        |> Message.SmsgMonsterMove.build()
        |> Network.send_packet(pid)
    end
  end

  defp deactivate_ai(%Mob{} = state) do
    state
    |> cancel_ai_tick()
    |> unwatch_chase()
  end

  defp schedule_ai_tick(%Mob{} = state, delay) when is_integer(delay) and delay >= 0 do
    state = cancel_ai_tick(state)
    token = make_ref()
    ref = Process.send_after(self(), {:ai_tick, token}, delay)
    put_ai_tick_ref(state, ref, token)
  end

  defp cancel_ai_tick(%Mob{internal: %Internal{ai_tick_ref: ref}} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    clear_ai_tick_ref(state)
  end

  defp cancel_ai_tick(%Mob{} = state), do: clear_ai_tick_ref(state)

  defp put_ai_tick_ref(%Mob{internal: %Internal{} = internal} = state, ref, token)
       when is_reference(ref) and is_reference(token) do
    %{state | internal: %{internal | ai_tick_ref: ref, ai_tick_token: token}}
  end

  defp clear_ai_tick_ref(%Mob{internal: %Internal{} = internal} = state) do
    %{state | internal: %{internal | ai_tick_ref: nil, ai_tick_token: nil}}
  end

  defp sync_chase_watch(%Mob{} = state) do
    case chase_watch(state) do
      {target, last_position, threshold} ->
        ChaseWatch.watch(target, self(), last_position, threshold)

      nil ->
        ChaseWatch.unwatch(self())
    end

    state
  end

  defp unwatch_chase(%Mob{} = state) do
    ChaseWatch.unwatch(self())
    state
  end

  defp chase_watch(
         %Mob{internal: %Internal{in_combat: true, blackboard: blackboard}, unit: %Unit{target: target}} = state
       )
       when is_integer(target) and target > 0 do
    case Blackboard.from_any(blackboard) do
      %Blackboard{last_target_pos: {x, y, z}} -> {target, {x, y, z}, MobBT.chase_repath_distance(state, target)}
      %Blackboard{} -> melee_hold_watch(state, target)
    end
  end

  defp chase_watch(%Mob{}), do: nil

  defp melee_hold_watch(%Mob{internal: %Internal{map: map}} = state, target) do
    with {^map, x, y, z} <- World.target_position(target),
         distance when is_number(distance) <- World.distance_to_guid(state, target) do
      {target, {x, y, z}, MobBT.melee_escape_distance(state, target, distance)}
    else
      _ -> nil
    end
  end

  defp mark_chase_ready(%Mob{internal: %Internal{blackboard: blackboard} = internal} = state) do
    blackboard = %{Blackboard.from_any(blackboard) | next_chase_at: 0}
    %{state | internal: %{internal | blackboard: blackboard}}
  end

  defp mark_aggro_ready(%Mob{internal: %Internal{blackboard: blackboard} = internal} = state) do
    blackboard = %{Blackboard.from_any(blackboard) | next_aggro_at: 0}
    %{state | internal: %{internal | blackboard: blackboard}}
  end

  defp engage_combat(%Mob{internal: %Internal{pet: %Pet{reaction_state: :passive}}} = state, _caster) do
    state
  end

  defp engage_combat(%Mob{internal: internal} = state, caster) when is_integer(caster) do
    now = Time.now()
    was_in_combat = internal.in_combat == true

    %{state | internal: %{internal | in_combat: true, last_hostile_time: now}}
    |> Threat.add(caster, 0)
    |> MobBT.reselect_victim()
    |> Combat.sync_combat_flag()
    |> maybe_tap(caster)
    |> maybe_eventai_enter_combat(was_in_combat, caster, now)
  end

  defp engage_combat(%Mob{} = state, _caster) do
    state
  end

  defp maybe_eventai_enter_combat(%Mob{} = state, true, _caster, _now), do: state

  defp maybe_eventai_enter_combat(%Mob{} = state, false, caster, now) do
    EventAI.with_blackboard(state, &EventAI.enter_combat(&1, &2, caster, now))
  end

  defp eventai_spell_hit(%Mob{} = state, caster_guid, %Spell{id: spell_id}) when is_integer(caster_guid) do
    EventAI.with_blackboard(state, &EventAI.on_spell_hit(&1, &2, caster_guid, spell_id, Time.now()))
  end

  defp eventai_spell_hit(%Mob{} = state, _caster_guid, _spell), do: state

  defp maybe_tap(
         %Mob{unit: %Unit{} = unit, internal: %Internal{loot: %Loot{tapped_by: nil} = loot} = internal} = state,
         caster
       ) do
    caster = controlling_player(caster)

    if not Core.dead?(state) and Guid.entity_type(caster) == :player do
      group_id =
        case PartySystem.group_of(caster) do
          %Party.Group{id: id} -> id
          _ -> nil
        end

      internal = %{internal | loot: %{loot | tapped_by: %{player: caster, group_id: group_id}}}
      unit = %{unit | dynamic_flags: (unit.dynamic_flags || 0) ||| @dynamic_flag_tapped}
      Metadata.update(state.object.guid, %{tapped_player: caster, tapped_group_id: group_id})

      %{state | unit: unit, internal: internal}
      |> Core.mark_broadcast_update()
    else
      state
    end
  end

  defp maybe_tap(%Mob{} = state, _caster), do: state

  defp maybe_finalize_death(%Mob{internal: %Internal{death_finalized?: true}} = state), do: state

  defp maybe_finalize_death(%Mob{internal: %Internal{pet: %Pet{}}} = state) do
    if Core.dead?(state) do
      Process.send_after(self(), :pet_stop, 100)

      state
      |> mark_death_finalized()
      |> Threat.wipe()
      |> Core.mark_broadcast_update()
    else
      state
    end
  end

  defp maybe_finalize_death(%Mob{} = state) do
    if Core.dead?(state) do
      killer = state.internal.killed_by

      state
      |> mark_death_finalized()
      |> Threat.wipe()
      |> EventAI.with_blackboard(&EventAI.on_death(&1, &2, killer, Time.now()))
      |> EventSink.emit_pending()
      |> maybe_decrement_on_death(killer)
      |> maybe_reward_kill(killer)
      |> Corpse.prepare(killer)
      |> Respawn.schedule()
      |> Core.mark_broadcast_update()
    else
      state
    end
  end

  defp mark_death_finalized(%Mob{internal: internal} = state) do
    %{state | internal: %{internal | death_finalized?: true}}
  end

  defp maybe_decrement_on_death(%Mob{} = state, target) when is_integer(target) and target > 0 do
    Metadata.decrement(target, :attacker_count, 0)
    state
  end

  defp maybe_decrement_on_death(%Mob{} = state, _target), do: state

  defp maybe_reward_kill(%Mob{} = state, target) when is_integer(target) and target > 0 do
    target = controlling_player(target)

    if Guid.entity_type(target) == :player do
      case PartySystem.group_of(target) do
        %Party.Group{} = group -> reward_group_kill(state, group)
        _ -> Entity.reward_kill(target, state)
      end
    end

    state
  end

  defp maybe_reward_kill(%Mob{} = state, _target), do: state

  defp reward_group_kill(%Mob{internal: %Internal{} = internal, unit: %Unit{} = unit} = state, group) do
    member_guids = MapSet.new(group.members, & &1.guid)

    eligible =
      state
      |> World.nearby_players(Experience.group_reward_distance())
      |> Enum.filter(fn {guid, _distance} -> MapSet.member?(member_guids, guid) end)
      |> Enum.flat_map(fn {guid, _distance} ->
        case Metadata.query(guid, [:level, :alive?]) do
          %{level: level, alive?: true} when is_integer(level) -> [%{guid: guid, level: level}]
          _ -> []
        end
      end)

    opts = [
      experience_multiplier: internal.creature.experience_multiplier,
      extra_flags: internal.creature.extra_flags,
      elite?: Experience.elite_rank?(internal.creature.rank)
    ]

    eligible
    |> Experience.group_shares(unit.level, opts)
    |> Enum.each(fn {guid, xp} -> Entity.reward_kill_share(guid, state, xp) end)
  end

  defp attacker_count(guid) do
    case Metadata.query(guid, [:attacker_count]) do
      %{attacker_count: count} when is_integer(count) and count > 0 -> count
      _ -> 1
    end
  end

  defp caster_guid(%{caster_guid: caster_guid}) when is_integer(caster_guid), do: caster_guid
  defp caster_guid(caster_guid) when is_integer(caster_guid), do: caster_guid
  defp caster_guid(_caster), do: nil

  defp controlling_player(guid) when is_integer(guid) do
    case Metadata.query(guid, [:owner_guid]) do
      %{owner_guid: owner_guid} when is_integer(owner_guid) and owner_guid > 0 -> owner_guid
      _ -> guid
    end
  end

  defp valid_pet_spell_target?(_state, %Spell{} = spell, target_guid) when target_guid in [0, nil],
    do: not Spell.requires_hostile_target?(spell)

  defp valid_pet_spell_target?(state, %Spell{} = spell, target_guid) do
    not Spell.requires_hostile_target?(spell) or Hostility.valid_attack_target?(state, target_guid)
  end
end
