defmodule ThistleTea.Game.World.Entity.Mob.Respawn do
  @moduledoc """
  Post-death respawn lifecycle for a mob: schedules the respawn timer when
  the mob dies, defers while loot rolls are pending, and rebuilds the mob at
  its spawn point (fresh tree, position, metadata) when the timer fires.
  Temporary summons stop instead of respawning: a typed summon follows its
  despawn timer and `SummonDespawn` rules, and stops once its corpse is gone.
  Script-driven despawns hide the mob immediately and ride the same respawn
  timer back in. Reviving a corpse respawns it alive in place; a spawn that is
  dead by default lies back down once its life runs out.
  """
  alias ThistleTea.Game.Core.AI.BT
  alias ThistleTea.Game.Core.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.SingleTarget
  alias ThistleTea.Game.Core.Aura.StealthDetection
  alias ThistleTea.Game.Core.Combat.CombatLeash
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Combat.FeignDeath
  alias ThistleTea.Game.Core.Creature.CreatureFlags
  alias ThistleTea.Game.Core.Creature.SummonDespawn
  alias ThistleTea.Game.Core.Creature.TemporaryFaction
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell.SpellResist
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity.AIEnvironment
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.FormationEnvironment
  alias ThistleTea.Game.World.Entity.Mob.Corpse
  alias ThistleTea.Game.World.Entity.Mob.CreatureEventEnvironment
  alias ThistleTea.Game.World.Entity.Mob.Incarnation
  alias ThistleTea.Game.World.Entity.NavigationResolver
  alias ThistleTea.Game.World.Loader.Faction, as: FactionLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.CreatureGroups
  alias ThistleTea.Game.World.System.SpawnPool
  alias ThistleTea.Game.World.Visibility

  @default_delay_ms 120_000

  def start_summon_timer(%Mob{internal: %Internal{spawn: %Spawn{despawn_delay_ms: delay} = spawn_state}} = state)
      when is_integer(delay) and delay > 0 do
    ref = make_ref()
    Process.send_after(self(), {:summon_despawn, ref}, delay)
    put_spawn(state, %{spawn_state | despawn_ref: ref})
  end

  def start_summon_timer(%Mob{} = state), do: state

  def summon_despawn_due(%Mob{internal: %Internal{spawn: %Spawn{despawn_type: type}} = internal} = state) do
    cond do
      charm_suspends_despawn?(internal.pet) -> :wait
      SummonDespawn.typed?(type) -> SummonDespawn.when_due(type, Entity.dead?(state), internal.in_combat == true)
      true -> :despawn
    end
  end

  defp charm_suspends_despawn?(%Pet{kind: :charmed}), do: true
  defp charm_suspends_despawn?(_pet), do: false

  def schedule(%Mob{internal: %{spawn: %Spawn{temporary?: true, despawn_type: type}}} = state)
      when is_integer(type) and type > 0 do
    case SummonDespawn.at_death(type) do
      :despawn -> remove_and_stop(state)
      :restart_timer -> start_summon_timer(state)
      :keep_corpse -> state
    end
  end

  def schedule(%Mob{internal: %Internal{spawn: %Spawn{respawn_ref: ref}}} = state) when is_reference(ref) do
    state
  end

  def schedule(%Mob{internal: %Internal{spawn: %Spawn{} = spawn_state} = internal} = state) do
    ref = Process.send_after(self(), :respawn, delay_ms(spawn_state.respawn_delay_ms))
    %{state | internal: %{internal | spawn: %{spawn_state | respawn_ref: ref}}}
  end

  def schedule(%Mob{} = state), do: state

  def after_corpse_removed(%Mob{internal: %{spawn: %Spawn{temporary?: true, despawn_type: type}}} = state)
      when is_integer(type) and type > 0 do
    if Corpse.removed?(state), do: remove_and_stop(state), else: state
  end

  def after_corpse_removed(%Mob{} = state), do: state

  def handle(%Mob{} = state) do
    cond do
      not Entity.dead?(state) ->
        kick_ai_tick()
        clear_ref(state)

      Corpse.pending?(state) ->
        put_spawn(state, %{state.internal.spawn | respawn_pending?: true})

      temporary?(state) ->
        remove_and_stop(state)

      true ->
        recycle_or_respawn(state)
    end
  end

  def force(%Mob{} = state, even_if_alive?) when is_boolean(even_if_alive?) do
    if Entity.dead?(state) or even_if_alive?, do: respawn(state), else: state
  end

  def revive(%Mob{} = state, life_ms) do
    if Entity.dead?(state) and not temporary?(state),
      do: state |> respawn(nil, revive?: true) |> schedule_rest(life_ms),
      else: state
  end

  def return_to_rest(%Mob{internal: %Internal{spawn: %Spawn{dead?: true}}} = state, incarnation_id) do
    if Incarnation.id(state) == incarnation_id and not Entity.dead?(state), do: respawn(state), else: state
  end

  def return_to_rest(%Mob{} = state, _incarnation_id), do: state

  defp schedule_rest(%Mob{} = state, life_ms) when is_integer(life_ms) do
    Process.send_after(self(), {:return_to_rest, Incarnation.id(state)}, life_ms)
    state
  end

  defp schedule_rest(%Mob{} = state, nil), do: state

  def force_group_member(%Mob{} = state) do
    if Entity.dead?(state), do: respawn(state, FormationEnvironment.respawn_position(state, Time.now())), else: state
  end

  def despawn(%Mob{} = state, respawn_delay_ms) do
    cond do
      temporary?(state) ->
        remove_and_stop(state)

      Corpse.removed?(state) ->
        state

      true ->
        %{entity: state} = Engagement.leave(state, :despawn, Time.now())
        state = EventSink.emit_pending(state)
        state = %{state | unit: %{state.unit | health: 0}}
        CreatureGroups.event(state, :despawn, self())
        Metadata.update(state.object.guid, %{alive?: false, health_pct: 0.0})

        state
        |> Corpse.remove()
        |> schedule_override(respawn_delay_ms)
    end
  end

  defp temporary?(%Mob{internal: %Internal{spawn: %Spawn{temporary?: true}}}), do: true
  defp temporary?(%Mob{}), do: false

  defp remove_and_stop(%Mob{} = state) do
    state = if Entity.dead?(state), do: Corpse.remove(state), else: state
    pid = self()

    Task.start(fn ->
      World.stop_entity(pid)
    end)

    state
  end

  defp schedule_override(%Mob{internal: %Internal{spawn: %Spawn{} = spawn_state} = internal} = state, respawn_delay_ms) do
    if is_reference(spawn_state.respawn_ref) do
      Process.cancel_timer(spawn_state.respawn_ref)
    end

    delay = if is_integer(respawn_delay_ms) and respawn_delay_ms > 0, do: respawn_delay_ms
    ref = Process.send_after(self(), :respawn, delay || delay_ms(spawn_state.respawn_delay_ms))
    %{state | internal: %{internal | spawn: %{spawn_state | respawn_ref: ref}}}
  end

  def maybe_continue(%Mob{internal: %Internal{spawn: %Spawn{respawn_pending?: true}}} = state) do
    if not Corpse.pending?(state) do
      send(self(), :respawn)
    end

    :ok
  end

  def maybe_continue(%Mob{} = _state), do: :ok

  defp respawn(%Mob{} = state, position \\ nil, opts \\ []) do
    now = Time.now()

    state =
      state
      |> CombatLeash.stop()
      |> EventSink.emit_pending()
      |> Corpse.remove()
      |> SingleTarget.detach(now, keep_self?: false)
      |> EventSink.emit_pending()
      |> Incarnation.renew()
      |> Mob.respawn(opts)
      |> CreatureEventEnvironment.reconcile(now)
      |> at_position(position)
      |> TemporaryFaction.after_respawn()
      |> Mob.apply_addon_auras(now)
      |> BT.init(MobBT.tree())
      |> register_group_respawn()
      |> EventAI.with_blackboard(&EventAI.on_spawned(&1, &2, now, AIEnvironment.context(&1, now)))
      |> NavigationResolver.resolve(now)
      |> put_spawn_position()
      |> broadcast_respawn()

    kick_ai_tick()
    state
  end

  defp at_position(state, nil), do: state

  defp at_position(%Mob{} = state, position),
    do: %{state | movement_block: %{state.movement_block | position: position}}

  defp register_group_respawn(%Mob{} = state) do
    CreatureGroups.respawn(state, self())
    state
  end

  defp recycle_or_respawn(%Mob{} = state) do
    case SpawnPool.recycle(state) do
      :pooled -> state
      :unpooled -> respawn(state)
    end
  end

  defp put_spawn_position(%Mob{} = state) do
    World.update_position(state)
    state = Visibility.join_entity(state)
    update_metadata(state)
    state
  end

  defp broadcast_respawn(%Mob{} = state) do
    UpdateObject.from_entity(state, :create_object2) |> World.broadcast_packet(state)
    state
  end

  defp update_metadata(%Mob{} = state) do
    metadata = %{
      bounding_radius: state.unit.bounding_radius,
      combat_reach: state.unit.combat_reach,
      level: state.unit.level,
      proximity_aggro?: Mob.proximity_aggro?(state),
      no_spell_defense?: CreatureFlags.has?(state, :no_spell_defense),
      unit_flags: state.unit.flags,
      transport_guid: state.movement_block.transport_guid,
      shapeshift_form: state.unit.shapeshift_form || 0,
      incarnation_id: Incarnation.id(state),
      alive?: state.unit.health > 0,
      feigning_death?: FeignDeath.successful?(state),
      victim_guid: state.unit.target,
      detect_range_modifier: Aura.flat_amount(state, :mod_detect_range),
      health_pct: Entity.health_pct(state),
      health_deficit: Entity.health_deficit(state),
      orientation: elem(state.movement_block.position, 3)
    }

    Metadata.update(state.object.guid, Map.merge(metadata, SpellResist.defense_snapshot(state)))
    Metadata.update(state.object.guid, Mob.visibility_metadata(state))
    Metadata.update(state.object.guid, StealthDetection.target_metadata(state))

    Metadata.update(state.object.guid, FactionLoader.metadata(state.unit.faction_template))
  end

  defp clear_ref(%Mob{internal: %Internal{spawn: %Spawn{} = spawn_state}} = state) do
    put_spawn(state, %{spawn_state | respawn_ref: nil})
  end

  defp clear_ref(%Mob{} = state), do: state

  defp put_spawn(%Mob{internal: %Internal{} = internal} = state, %Spawn{} = spawn_state) do
    %{state | internal: %{internal | spawn: spawn_state}}
  end

  defp delay_ms(delay) when is_integer(delay) and delay >= 0, do: delay
  defp delay_ms(_delay), do: @default_delay_ms

  defp kick_ai_tick do
    Process.send_after(self(), :ai_tick, 0)
  end
end
