defmodule ThistleTea.Game.World.Battleground.Buffs do
  @moduledoc "Owns rotating battleground pickups, their three-minute respawn, and match-lifetime cleanup."
  use GenServer

  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Battleground.BuffRegistry
  alias ThistleTea.Game.World.Battleground.Supervisor, as: MatchSupervisor
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader

  require Logger

  @registry BuffRegistry
  @entries [179_871, 179_904, 179_905]
  @respawn_ms 180_000

  def start(world, owner, positions) do
    DynamicSupervisor.start_child(MatchSupervisor, {__MODULE__, world: world, owner: owner, positions: positions})
  end

  def stop(world) do
    case GenServer.whereis(via(world)) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: via(Keyword.fetch!(opts, :world)))

  def child_spec(opts) do
    %{id: {__MODULE__, Keyword.fetch!(opts, :world)}, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  @impl GenServer
  def init(opts) do
    state = %{
      world: Keyword.fetch!(opts, :world),
      owner: Process.monitor(Keyword.fetch!(opts, :owner)),
      positions:
        Keyword.fetch!(opts, :positions) |> Enum.with_index() |> Map.new(fn {position, index} -> {index, position} end),
      running: %{},
      monitors: %{},
      respawn_ms: Keyword.get(opts, :respawn_ms, @respawn_ms),
      choose: Keyword.get(opts, :choose, &Enum.random/1),
      spawn: Keyword.get(opts, :spawn, &spawn_pickup/3),
      stop: Keyword.get(opts, :stop, &World.stop_entity/1)
    }

    {:ok, Enum.reduce(Map.keys(state.positions), state, &spawn_at(&2, &1))}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{owner: ref} = state), do: {:stop, :normal, state}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _monitors} ->
        {:noreply, state}

      {index, monitors} ->
        Process.send_after(self(), {:respawn, index}, state.respawn_ms)
        {:noreply, %{state | running: Map.delete(state.running, index), monitors: monitors}}
    end
  rescue
    error ->
      Logger.error("Battleground pickup removal failed: #{Exception.message(error)}")
      {:noreply, state}
  end

  def handle_info({:respawn, index}, state), do: {:noreply, spawn_at(state, index)}

  @impl GenServer
  def terminate(_reason, state) do
    Enum.each(state.running, fn {_index, pid} -> state.stop.(pid) end)
    :ok
  end

  defp spawn_at(state, index) do
    if Map.has_key?(state.running, index) do
      state
    else
      position = Map.fetch!(state.positions, index)
      entry = state.choose.(@entries)

      case state.spawn.(state.world, entry, position) do
        {:ok, pid} ->
          ref = Process.monitor(pid)
          %{state | running: Map.put(state.running, index, pid), monitors: Map.put(state.monitors, ref, index)}

        error ->
          Logger.error("Battleground pickup spawn failed: #{inspect(error)}")
          Process.send_after(self(), {:respawn, index}, state.respawn_ms)
          state
      end
    end
  rescue
    error ->
      Logger.error("Battleground pickup spawn failed: #{Exception.message(error)}")
      Process.send_after(self(), {:respawn, index}, state.respawn_ms)
      state
  end

  defp spawn_pickup(world, entry, position) do
    case TemplateLoader.cached(entry) do
      nil ->
        {:error, :missing_template}

      template ->
        object = GameObject.build_summoned(template, world, position)
        trap = %{object.internal.trap | charges: 1, radius: 3.0}
        World.start_incarnation(%{object | internal: %{object.internal | trap: trap}})
    end
  end

  defp via(world), do: {:via, Registry, {@registry, world}}
end
