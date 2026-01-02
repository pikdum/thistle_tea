defmodule ThistleTea.Game.Entity.Server.Mob do
  use GenServer

  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.HTN
  alias ThistleTea.Game.Entity.Logic.AI.HTN.Mob, as: MobHTN
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.System.GameEvent

  def start_link(%Mob{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl GenServer
  def init(%Mob{} = state) do
    GameEvent.subscribe(state)
    Process.flag(:trap_exit, true)
    Core.set_position(state)

    {state, delay} = HTN.start(state, MobHTN.htn())
    schedule_ai(delay)

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
    state = engage_combat(state, caster)
    {:ok, state} = Core.take_damage(state, 5)
    Core.update_packet(state) |> World.broadcast_packet(state)
    state = HTN.interrupt(state)
    schedule_ai(0)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:receive_attack, attack}, state) do
    state = engage_combat(state, Map.get(attack, :caster))
    state = HTN.interrupt(state)
    schedule_ai(0)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:ai, state) do
    {state, delay} = HTN.step(state, MobHTN.htn())
    schedule_ai(delay)
    {:noreply, state}
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
  def handle_call(:get_entity, _from, state), do: {:reply, :mob, state}

  @impl GenServer
  def handle_call(:get_name, _from, state), do: {:reply, state.internal.name, state}

  @impl GenServer
  def terminate(_reason, state), do: Core.remove_position(state)

  defp schedule_ai(delay) when is_integer(delay) and delay >= 0 do
    Process.send_after(self(), :ai, delay)
  end

  defp engage_combat(%Mob{unit: unit, internal: internal} = state, caster) when is_integer(caster) do
    %{state | unit: %{unit | target: caster}, internal: %{internal | in_combat: true}}
  end

  defp engage_combat(%Mob{} = state, _caster) do
    state
  end

end
