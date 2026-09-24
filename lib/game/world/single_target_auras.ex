defmodule ThistleTea.Game.World.SingleTargetAuras do
  @moduledoc """
  Serializes caster-limited aura claims published by recipient owners.
  Replacements send generation-checked removals directly to the recorded
  recipient process. Monitors retire both sides of a departed entity without
  calling another entity owner or writing its state.
  """

  use GenServer

  alias ThistleTea.Game.Aura.SingleTargetClaim
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Logic.Aura.SingleTarget
  alias ThistleTea.Game.World

  require Logger

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, nil, Keyword.put_new(opts, :name, __MODULE__))

  def sync(guid, owner, world, claims, server \\ __MODULE__) when is_pid(owner),
    do: GenServer.call(server, {:sync, guid, owner, world, claims})

  def leave(guid, owner, server \\ __MODULE__), do: GenServer.call(server, {:leave, guid, owner})

  def caster_died(guid, owner, server \\ __MODULE__), do: GenServer.call(server, {:caster_died, guid, owner})

  @impl GenServer
  def init(_opts), do: {:ok, %{owners: %{}, monitors: %{}, targets: %{}, sources: %{}}}

  @impl GenServer
  def handle_call({:sync, guid, owner, world, claims}, _from, state) do
    state = monitor_owner(state, guid, owner)
    previous = Map.get(state.targets, guid, [])
    state = Enum.reduce(previous -- claims, state, &unregister/2)
    state = %{state | targets: Map.put(state.targets, guid, claims)}
    state = Enum.reduce(claims -- previous, state, &register(&2, &1, owner, world))
    {:reply, :ok, state}
  rescue
    error ->
      Logger.error("Single-target aura publication failed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:reply, {:error, error}, state}
  end

  def handle_call({:leave, guid, owner}, _from, state) do
    state = if Map.get(state.owners, guid) == owner, do: forget(state, guid), else: state
    {:reply, :ok, state}
  rescue
    error ->
      Logger.error("Single-target aura departure failed: #{Exception.message(error)}")
      {:reply, {:error, error}, state}
  end

  def handle_call({:caster_died, guid, owner}, _from, state) do
    state =
      if Map.get(state.owners, guid) == owner do
        state.sources
        |> Map.get(guid, [])
        |> Enum.filter(fn {claim, _owner} -> claim.stalked? end)
        |> Enum.reduce(state, fn {claim, recipient}, current ->
          remove(recipient, claim, :death)
          unregister(claim, current)
        end)
      else
        state
      end

    {:reply, :ok, state}
  rescue
    error ->
      Logger.error("Single-target aura death cleanup failed: #{Exception.message(error)}")
      {:reply, {:error, error}, state}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _owner, _reason}, state) do
    state =
      case Map.get(state.monitors, ref) do
        nil -> state
        guid -> forget(state, guid)
      end

    {:noreply, state}
  rescue
    error ->
      Logger.error("Single-target aura owner cleanup failed: #{Exception.message(error)}")
      {:noreply, state}
  end

  defp register(state, %SingleTargetClaim{} = claim, recipient, world) do
    case Entity.pid(claim.caster_guid) do
      caster when is_pid(caster) ->
        state = monitor_owner(state, claim.caster_guid, caster)

        if same_world?(claim.caster_guid, world) do
          claim_target(state, claim, recipient)
        else
          remove(recipient, claim, :removed)
          state
        end

      nil ->
        state
    end
  end

  defp same_world?(guid, world) do
    case World.position(guid) do
      {^world, _, _, _} -> true
      nil -> true
      _position -> false
    end
  end

  defp claim_target(state, claim, recipient) do
    {replaced, retained} =
      state.sources
      |> Map.get(claim.caster_guid, [])
      |> Enum.split_with(fn {previous, _owner} -> SingleTarget.conflicts?(previous, claim) end)

    Enum.each(replaced, fn {previous, owner} -> remove(owner, previous, :removed) end)
    %{state | sources: Map.put(state.sources, claim.caster_guid, [{claim, recipient} | retained])}
  end

  defp unregister(claim, state) do
    sources = Map.get(state.sources, claim.caster_guid, [])
    retained = Enum.reject(sources, fn {previous, _owner} -> previous == claim end)

    sources =
      if retained == [],
        do: Map.delete(state.sources, claim.caster_guid),
        else: Map.put(state.sources, claim.caster_guid, retained)

    %{state | sources: sources}
  end

  defp monitor_owner(state, guid, owner) do
    if Map.get(state.owners, guid) == owner do
      state
    else
      state = forget(state, guid)
      ref = Process.monitor(owner)
      %{state | owners: Map.put(state.owners, guid, owner), monitors: Map.put(state.monitors, ref, guid)}
    end
  end

  defp forget(state, guid) do
    Enum.each(Map.get(state.sources, guid, []), fn {claim, recipient} ->
      if claim.target_guid != guid, do: remove(recipient, claim, :removed)
    end)

    state = Enum.reduce(Map.get(state.targets, guid, []), state, &unregister/2)

    monitors =
      Map.reject(state.monitors, fn {ref, monitored} ->
        if monitored == guid do
          Process.demonitor(ref, [:flush])
          true
        else
          false
        end
      end)

    %{
      state
      | owners: Map.delete(state.owners, guid),
        monitors: monitors,
        targets: Map.delete(state.targets, guid),
        sources: Map.delete(state.sources, guid)
    }
  end

  defp remove(owner, claim, cause), do: GenServer.cast(owner, {:remove_single_target_aura, claim, cause})
end
