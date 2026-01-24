defmodule ThistleTea.Game.Entity.Server.GameObject do
  use GenServer

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.System.GameEvent

  def start_link(%GameObject{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl GenServer
  def init(%GameObject{} = state) do
    GameEvent.subscribe(state)
    Process.flag(:trap_exit, true)
    Entity.register(state.object.guid)
    Core.set_position(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    Core.update_packet(state)
    |> Network.send_packet(pid)

    {:noreply, state}
  end

  @impl GenServer
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
  def terminate(_reason, state), do: Core.remove_position(state)
end
