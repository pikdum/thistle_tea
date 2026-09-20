defmodule ThistleTea.Game.World.System.Honor do
  @moduledoc """
  Owns runtime honor accounting and serializes awards with calendar settlement.
  Players receive change notices and fetch current projections in their own
  process, so queued notices cannot restore an older honor snapshot.
  """
  use GenServer

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Honor.Award
  alias ThistleTea.Game.Entity.Data.Honor.Entry
  alias ThistleTea.Game.Entity.Data.Honor.Snapshot
  alias ThistleTea.Game.Entity.Logic.Honor.Ledger
  alias ThistleTea.Game.World.HonorStore

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def register(guid, team, level, server \\ __MODULE__) do
    GenServer.call(server, {:register, guid, team, level})
  end

  def snapshot(guid, server \\ __MODULE__), do: GenServer.call(server, {:snapshot, guid})

  def award(guid, %Award{} = award, server \\ __MODULE__) do
    GenServer.cast(server, {:award, guid, award})
  end

  def player_kill(victim_guid, shares, server \\ __MODULE__) when is_map(shares) do
    GenServer.cast(server, {:player_kill, victim_guid, shares})
  end

  @impl GenServer
  def init(opts) do
    day = Keyword.get(opts, :day, fn -> Integer.floor_div(System.system_time(:second), 86_400) end)
    table = Keyword.get(opts, :table, HonorStore)
    ledger = HonorStore.load(day.(), Keyword.get(opts, :weekday, 2), table)

    state = %{
      ledger: ledger,
      table: table,
      weekday: Keyword.get(opts, :weekday, 2),
      day: day,
      notify: Keyword.get(opts, :notify, &notify/2),
      tick_ms: Keyword.get(opts, :tick_ms, 60_000)
    }

    state = advance(state)
    Enum.each(state.ledger.entries, fn {guid, _entry} -> state.notify.(guid, nil) end)
    schedule_tick(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:register, guid, team, level}, _from, state) do
    state = advance(state)
    ledger = Ledger.register(state.ledger, guid, team, level)
    HonorStore.save(ledger, [guid], state.table)
    {:reply, project(ledger, guid), %{state | ledger: ledger}}
  rescue
    error ->
      Logger.error("Honor registration failed: #{Exception.message(error)}")
      {:reply, nil, recover(state)}
  end

  def handle_call({:snapshot, guid}, _from, state) do
    state = advance(state)
    {:reply, project(state.ledger, guid), state}
  rescue
    error ->
      Logger.error("Honor snapshot failed: #{Exception.message(error)}")
      {:reply, nil, recover(state)}
  end

  @impl GenServer
  def handle_cast({:award, guid, award}, state) do
    state = advance(state)
    ledger = Ledger.award(state.ledger, guid, award)
    awards = if ledger == state.ledger, do: [], else: [{guid, award}]
    {:noreply, commit(state, ledger, awards)}
  rescue
    error ->
      Logger.error("Honor award failed: #{Exception.message(error)}")
      {:noreply, recover(state)}
  end

  def handle_cast({:player_kill, victim_guid, shares}, state) do
    state = advance(state)

    {ledger, awards} =
      shares
      |> Enum.sort()
      |> Enum.reduce({state.ledger, []}, fn {guid, share}, {ledger, awards} ->
        case Ledger.player_kill(ledger, guid, victim_guid, share) do
          {ledger, nil} -> {ledger, awards}
          {ledger, award} -> {ledger, [{guid, award} | awards]}
        end
      end)

    {:noreply, commit(state, ledger, awards)}
  rescue
    error ->
      Logger.error("Honor kill credit failed: #{Exception.message(error)}")
      {:noreply, recover(state)}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    schedule_tick(state)
    {:noreply, advance(state)}
  rescue
    error ->
      Logger.error("Honor calendar update failed: #{Exception.message(error)}")
      {:noreply, recover(state)}
  end

  defp commit(state, ledger, awards) do
    HonorStore.save(ledger, Enum.map(awards, &elem(&1, 0)), state.table)
    Enum.each(awards, fn {guid, award} -> state.notify.(guid, award) end)
    %{state | ledger: ledger}
  end

  defp advance(state) do
    ledger = Ledger.advance(state.ledger, state.day.())

    if ledger.day != state.ledger.day do
      guids = Map.keys(ledger.entries)
      HonorStore.save(ledger, guids, state.table)
      Enum.each(guids, &state.notify.(&1, nil))
    end

    %{state | ledger: ledger}
  end

  defp recover(state), do: %{state | ledger: HonorStore.load(state.day.(), state.weekday, state.table)}

  defp project(ledger, guid) do
    case Map.get(ledger.entries, guid) do
      %Entry{honor: honor} -> %Snapshot{honor: honor, day: ledger.day, week_start: ledger.week_start}
      nil -> nil
    end
  end

  defp notify(guid, award) do
    case Entity.pid(guid) do
      pid when is_pid(pid) -> GenServer.cast(pid, {:honor_updated, award})
      _offline -> :ok
    end
  end

  defp schedule_tick(%{tick_ms: milliseconds}) when is_integer(milliseconds) do
    Process.send_after(self(), :tick, milliseconds)
  end

  defp schedule_tick(_state), do: :ok
end
