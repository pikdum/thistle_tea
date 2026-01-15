defmodule ThistleTea.Game.Entity.Server.Mob do
  use GenServer

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.GameEvent

  @ai_tick_ms 100

  def start_link(%Mob{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl GenServer
  def init(%Mob{} = state) do
    GameEvent.subscribe(state)
    Process.flag(:trap_exit, true)
    state = BT.init(state, MobBT.tree())
    Core.set_position(state)

    schedule_ai_tick(500)

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    Core.update_packet(state)
    |> Network.send_packet(pid)

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:move_to, x, y, z}, state) do
    state = Movement.move_to(state, {x, y, z})
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:receive_spell, caster, _spell_id}, state) do
    state =
      state
      |> maybe_reset_attack_started(caster)
      |> engage_combat(caster)

    target = state.unit.target

    state =
      state
      |> Core.take_damage(10)
      |> maybe_decrement_on_death(target)

    schedule_ai_tick(0)
    {:noreply, state, {:continue, :maybe_broadcast}}
  end

  @impl GenServer
  def handle_cast({:receive_attack, %{caster: caster} = attack}, state) do
    damage = Combat.attack_damage(attack)

    state =
      state
      |> maybe_reset_attack_started(caster)
      |> engage_combat(caster)

    target = state.unit.target

    state =
      state
      |> Core.take_damage(damage)
      |> maybe_decrement_on_death(target)

    Combat.attacker_state_update(Map.get(attack, :caster, 0), state.object.guid, damage, attack)
    |> World.broadcast_packet(state)

    schedule_ai_tick(0)
    {:noreply, state, {:continue, :maybe_broadcast}}
  end

  @impl GenServer
  def handle_info(:ai_tick, %{internal: %Internal{behavior_tree: behavior_tree}} = state) do
    state = Movement.sync_position(state)
    Core.set_position(state)
    {status, state} = BT.tick(behavior_tree, state)
    schedule_ai_tick(ai_tick_delay(status))
    {:noreply, state, {:continue, :maybe_broadcast}}
  rescue
    _ -> {:noreply, state}
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
    Core.update_packet(state, update_type) |> World.broadcast_packet(state)
    internal = %{state.internal | broadcast_update?: false}
    {:noreply, %{state | internal: internal}}
  end

  def handle_continue(:maybe_broadcast, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_entity, _from, state), do: {:reply, :mob, state}

  @impl GenServer
  def terminate(_reason, state), do: Core.remove_position(state)

  defp schedule_ai_tick(delay) when is_integer(delay) and delay >= 0 do
    Process.send_after(self(), :ai_tick, delay)
  end

  defp ai_tick_delay({:running, delay_ms}) when is_integer(delay_ms) and delay_ms >= 0 do
    delay_ms
  end

  defp ai_tick_delay(_status), do: @ai_tick_ms

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

  defp maybe_decrement_on_death(state, target) do
    if Core.dead?(state) and is_integer(target) and target > 0 do
      Metadata.decrement(target, :attacker_count, 0)
    end

    state
  end
end
