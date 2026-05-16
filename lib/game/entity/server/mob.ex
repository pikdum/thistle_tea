defmodule ThistleTea.Game.Entity.Server.Mob do
  use GenServer

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.GameEvent

  @ai_tick_ms 100
  @ai_tick_max_ms 1_000
  @default_respawn_delay_ms 120_000

  def start_link(%Mob{} = state) do
    GenServer.start_link(__MODULE__, state, name: EntityRegistry.via(state.object.guid))
  end

  @impl GenServer
  def init(%Mob{} = state) do
    GameEvent.subscribe(state)
    Process.flag(:trap_exit, true)
    state = BT.init(state, MobBT.tree())
    Core.set_position(state)

    schedule_ai_tick(0)

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    state = Movement.sync_position(state)
    Core.set_position(state)

    Core.update_object(state)
    |> Network.send_packet(pid)

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:move_to, x, y, z}, state) do
    state = Movement.move_to(state, {x, y, z})
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:receive_spell, caster, spell}, state) do
    caster_guid = caster_guid(caster)

    state =
      state
      |> maybe_reset_attack_started(caster_guid)
      |> engage_combat(caster_guid)

    target = state.unit.target
    dead_before = Core.dead?(state)

    {state, events} = SpellEffect.receive(state, caster, spell)

    state =
      state
      |> EventSink.emit(events)
      |> handle_death_transition(target, dead_before)

    schedule_ai_tick(0)
    {:noreply, state, {:continue, :maybe_broadcast}}
  end

  @impl GenServer
  def handle_cast({:receive_attack, %{caster: caster} = attack}, state) do
    state =
      state
      |> maybe_reset_attack_started(caster)
      |> engage_combat(caster)

    target = state.unit.target
    dead_before = Core.dead?(state)

    {state, events} = Combat.receive_attack(state, attack)

    state =
      state
      |> handle_death_transition(target, dead_before)
      |> EventSink.emit(events)

    schedule_ai_tick(0)
    {:noreply, state, {:continue, :maybe_broadcast}}
  end

  @impl GenServer
  def handle_info(:ai_tick, %{internal: %Internal{behavior_tree: behavior_tree}} = state) do
    state = Movement.sync_position(state)
    Core.set_position(state)
    {status, state} = BT.tick(behavior_tree, state)
    state = EventSink.emit_pending(state)
    schedule_ai_tick(ai_tick_delay(status))
    {:noreply, state, {:continue, :maybe_broadcast}}
  rescue
    _ -> {:noreply, state}
  end

  def handle_info(:respawn, %Mob{} = state) do
    state =
      if Core.dead?(state) do
        state
        |> Mob.respawn()
        |> BT.init(MobBT.tree())
        |> put_spawn_position()
        |> broadcast_respawn()
      else
        clear_respawn_ref(state)
      end

    schedule_ai_tick(0)
    {:noreply, state}
  end

  def handle_info({:event_stop, _event}, state) do
    pid = self()

    Task.start(fn ->
      World.stop_entity(pid)
    end)

    {:noreply, state}
  end

  def handle_info({:event_start, _event}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_continue(:maybe_broadcast, %{internal: %Internal{broadcast_update?: true}} = state) do
    update_type = if Core.dead?(state), do: :create_object2, else: :values
    Core.update_object(state, update_type) |> World.broadcast_packet(state)
    Metadata.update(state.object.guid, %{alive?: not Core.dead?(state)})
    internal = %{state.internal | broadcast_update?: false}
    {:noreply, %{state | internal: internal}}
  end

  def handle_continue(:maybe_broadcast, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state), do: Core.remove_position(state)

  defp schedule_ai_tick(delay) when is_integer(delay) and delay >= 0 do
    Process.send_after(self(), :ai_tick, delay)
  end

  defp ai_tick_delay({:running, delay_ms}) when is_integer(delay_ms) and delay_ms >= 0 do
    min(delay_ms, @ai_tick_max_ms)
  end

  defp ai_tick_delay(_status), do: @ai_tick_ms

  defp put_spawn_position(%Mob{} = state) do
    Core.set_position(state)
    update_metadata(state)
    state
  end

  defp broadcast_respawn(%Mob{} = state) do
    Core.update_object(state, :create_object2) |> World.broadcast_packet(state)
    state
  end

  defp engage_combat(%Mob{unit: %Unit{target: current_target} = unit, internal: internal} = state, caster)
       when is_integer(caster) do
    now = Time.now()

    state = update_attacker_count(state, current_target, caster)

    %{
      state
      | unit: %{unit | target: caster},
        internal: %{internal | in_combat: true, last_hostile_time: now}
    }
  end

  defp engage_combat(%Mob{} = state, _caster) do
    state
  end

  defp maybe_reset_attack_started(%Mob{unit: %Unit{target: target}} = state, caster) when is_integer(caster) do
    if target == caster do
      state
    else
      BT.reset_attack_started(state)
    end
  end

  defp maybe_reset_attack_started(state, _caster), do: state

  defp update_attacker_count(%Mob{} = state, current_target, caster) do
    if is_integer(current_target) and current_target > 0 and current_target != caster do
      Metadata.decrement(current_target, :attacker_count, 0)
    end

    if is_integer(caster) and caster > 0 and current_target != caster do
      Metadata.increment(caster, :attacker_count)
    end

    state
  end

  defp update_attacker_count(state, _current_target, _caster), do: state

  defp handle_death_transition(%Mob{} = state, target, false) do
    if Core.dead?(state) do
      state
      |> maybe_decrement_on_death(target)
      |> maybe_reward_kill(target)
      |> schedule_respawn()
    else
      state
    end
  end

  defp handle_death_transition(%Mob{} = state, _target, _dead_before), do: state

  defp maybe_decrement_on_death(%Mob{} = state, target) when is_integer(target) and target > 0 do
    Metadata.decrement(target, :attacker_count, 0)
    state
  end

  defp maybe_decrement_on_death(%Mob{} = state, _target), do: state

  defp maybe_reward_kill(%Mob{} = state, target) when is_integer(target) and target > 0 do
    if Guid.entity_type(target) == :player do
      Entity.reward_kill(target, state)
    end

    state
  end

  defp maybe_reward_kill(%Mob{} = state, _target), do: state

  defp caster_guid(%{caster_guid: caster_guid}) when is_integer(caster_guid), do: caster_guid
  defp caster_guid(caster_guid) when is_integer(caster_guid), do: caster_guid
  defp caster_guid(_caster), do: nil

  defp schedule_respawn(%Mob{internal: %Internal{respawn_ref: ref}} = state) when is_reference(ref) do
    state
  end

  defp schedule_respawn(%Mob{internal: %Internal{} = internal} = state) do
    ref = Process.send_after(self(), :respawn, respawn_delay_ms(internal.respawn_delay_ms))
    %{state | internal: %{internal | respawn_ref: ref}}
  end

  defp clear_respawn_ref(%Mob{internal: %Internal{} = internal} = state) do
    %{state | internal: %{internal | respawn_ref: nil}}
  end

  defp respawn_delay_ms(delay) when is_integer(delay) and delay >= 0, do: delay
  defp respawn_delay_ms(_delay), do: @default_respawn_delay_ms

  defp update_metadata(%Mob{} = state) do
    Metadata.update(state.object.guid, %{
      bounding_radius: state.unit.bounding_radius,
      combat_reach: state.unit.combat_reach,
      level: state.unit.level,
      alive?: state.unit.health > 0
    })
  end
end
