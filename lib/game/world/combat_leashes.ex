defmodule ThistleTea.Game.World.CombatLeashes do
  @moduledoc """
  Owns shared leash clocks for creatures recruited into the same fight.
  Owners publish typed transitions; ticks read an immutable ETS projection.
  Clocks survive the initiating creature's departure until their last member leaves.
  """
  use GenServer

  alias ThistleTea.Game.Entity.Data.CombatLeash.Owner
  alias ThistleTea.Game.Entity.Data.CombatLeash.Ref
  alias ThistleTea.Game.Entity.Logic.CombatLeash

  require Logger

  @table :combat_leashes

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  def event(%Ref{} = ref, event, owner, server \\ __MODULE__) when is_pid(owner),
    do: GenServer.call(server, {:event, ref, event, owner})

  def last_extended_at(entity_or_ref, server \\ __MODULE__)

  def last_extended_at(%Ref{} = ref, __MODULE__) do
    if :ets.whereis(@table) != :undefined, do: lookup(@table, ref)
  end

  def last_extended_at(%Ref{} = ref, server), do: GenServer.call(server, {:snapshot, ref})
  def last_extended_at(nil, _server), do: nil
  def last_extended_at(entity, server), do: last_extended_at(CombatLeash.reference(entity), server)

  def stop_world(world, server \\ __MODULE__), do: GenServer.call(server, {:stop_world, world})

  @impl GenServer
  def init(opts) do
    options = [:protected, read_concurrency: true]
    options = if Keyword.get(opts, :name, __MODULE__) == __MODULE__, do: [:named_table | options], else: options
    {:ok, %{actors: %{}, clocks: %{}, monitors: %{}, table: :ets.new(@table, options)}}
  end

  @impl GenServer
  def handle_call(request, _from, state) do
    handle_request(request, state)
  rescue
    error ->
      Logger.error("combat leash request crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:reply, {:error, :invalid_leash_transition}, state}
  end

  defp handle_request({:snapshot, ref}, state), do: {:reply, lookup(state.table, ref), state}

  defp handle_request({:stop_world, world}, state) do
    keys = state.actors |> Map.keys() |> Enum.filter(&(elem(&1, 0) == world))
    {:reply, :ok, Enum.reduce(keys, state, &detach(&2, &1))}
  end

  defp handle_request({:event, %Ref{} = ref, {:start, now, source}, owner}, state) when is_integer(now) do
    case start_status(state.actors[key(ref)], ref, owner) do
      :same ->
        {:reply, :ok, state}

      :stale ->
        {:reply, :stale, state}

      :new ->
        {:reply, :ok, start_fight(state, ref, source, now, owner)}
    end
  end

  defp handle_request({:event, %Ref{} = ref, event, owner}, state) do
    case state.actors[key(ref)] do
      %{ref: ^ref, owner: ^owner} = actor ->
        {:reply, :ok, transition(state, actor, event)}

      %{ref: %{incarnation: incarnation}, owner: ^owner, active?: false} = actor
      when incarnation == ref.incarnation and event == :stop ->
        {:reply, :ok, transition(state, actor, event)}

      _stale ->
        {:reply, :stale, state}
    end
  end

  defp start_status(nil, _ref, _owner), do: :new
  defp start_status(%{ref: ref, owner: owner}, ref, owner), do: :same

  defp start_status(%{ref: previous, owner: owner}, ref, owner) do
    if newer_reference?(ref, previous), do: :new, else: :stale
  end

  defp start_status(%{ref: previous}, ref, _owner) do
    if (ref.incarnation || 0) > (previous.incarnation || 0), do: :new, else: :stale
  end

  defp newer_reference?(ref, previous) do
    {ref.incarnation || 0, ref.generation} > {previous.incarnation || 0, previous.generation}
  end

  defp start_fight(state, ref, nil, now, owner) do
    case state.actors[key(ref)] do
      %{ref: %{incarnation: incarnation}, owner: ^owner, active?: false} = actor
      when incarnation == ref.incarnation ->
        actor = %{actor | ref: ref, active?: true}
        state = %{state | actors: Map.put(state.actors, key(ref), actor)}
        :ets.insert(state.table, {key(ref), ref, state.clocks[actor.clock].time})
        transition(state, actor, {:extend, now})

      _active ->
        start_linked_fight(state, ref, nil, now, owner)
    end
  end

  defp start_fight(state, ref, source, now, owner), do: start_linked_fight(state, ref, source, now, owner)

  defp start_linked_fight(state, ref, source, now, owner) do
    state = detach(state, key(ref))
    {clock, state} = source_clock(state, ref.world, source, now)
    attach(state, ref, owner, clock, true)
  end

  defp attach(state, ref, owner, clock, active?) do
    monitor = Process.monitor(owner)
    actor = %{ref: ref, owner: owner, monitor: monitor, clock: clock, active?: active?}
    shared = Map.update!(state.clocks[clock], :members, &MapSet.put(&1, key(ref)))

    state = %{
      state
      | actors: Map.put(state.actors, key(ref), actor),
        monitors: Map.put(state.monitors, monitor, key(ref)),
        clocks: Map.put(state.clocks, clock, shared)
    }

    :ets.insert(state.table, {key(ref), ref, shared.time})
    state
  end

  @impl GenServer
  def handle_info({:DOWN, monitor, :process, _owner, _reason}, state) do
    case state.monitors[monitor] do
      nil -> {:noreply, state}
      key -> {:noreply, detach(state, key)}
    end
  rescue
    error ->
      Logger.error("combat leash cleanup crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  defp source_clock(state, world, %Ref{world: world} = source, now) do
    case state.actors[key(source)] do
      %{ref: ^source, clock: clock} -> {clock, state}
      _stale -> new_clock(state, now)
    end
  end

  defp source_clock(state, world, %Owner{world: world} = source, now) do
    ref = %Ref{world: world, guid: source.guid, incarnation: source.incarnation, generation: 0}

    case state.actors[key(ref)] do
      %{ref: %{incarnation: incarnation}, owner: owner, clock: clock}
      when incarnation == source.incarnation and owner == source.pid ->
        {clock, state}

      nil ->
        owner_clock(state, ref, source.pid, now)

      %{ref: %{incarnation: incarnation}} when incarnation < source.incarnation ->
        state |> detach(key(ref)) |> owner_clock(ref, source.pid, now)

      _stale ->
        new_clock(state, now)
    end
  end

  defp source_clock(state, _world, _source, now), do: new_clock(state, now)

  defp owner_clock(state, ref, owner, now) do
    {clock, state} = new_clock(state, now)
    {clock, attach(state, ref, owner, clock, false)}
  end

  defp new_clock(state, now) do
    clock = make_ref()
    {clock, %{state | clocks: Map.put(state.clocks, clock, %{time: now, members: MapSet.new()})}}
  end

  defp transition(state, %{clock: clock}, {:extend, now}) when is_integer(now) do
    shared = state.clocks[clock]

    if now > shared.time do
      Enum.each(shared.members, fn key -> :ets.insert(state.table, {key, state.actors[key].ref, now}) end)
      %{state | clocks: Map.put(state.clocks, clock, %{shared | time: now})}
    else
      state
    end
  end

  defp transition(state, %{ref: ref}, :stop), do: detach(state, key(ref))
  defp transition(state, _actor, _event), do: state

  defp detach(state, key) do
    case Map.pop(state.actors, key) do
      {nil, _actors} -> state
      {actor, actors} -> detach_actor(%{state | actors: actors}, key, actor)
    end
  end

  defp detach_actor(state, key, actor) do
    Process.demonitor(actor.monitor, [:flush])
    :ets.delete(state.table, key)
    shared = state.clocks[actor.clock]
    members = MapSet.delete(shared.members, key)

    clocks =
      if MapSet.size(members) == 0,
        do: Map.delete(state.clocks, actor.clock),
        else: Map.put(state.clocks, actor.clock, %{shared | members: members})

    %{state | clocks: clocks, monitors: Map.delete(state.monitors, actor.monitor)}
  end

  defp lookup(table, ref) do
    case :ets.lookup(table, key(ref)) do
      [{_, ^ref, now}] -> now
      _missing -> nil
    end
  end

  defp key(%Ref{world: world, guid: guid}), do: {world, guid}
end
