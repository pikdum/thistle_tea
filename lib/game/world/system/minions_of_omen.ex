defmodule ThistleTea.Game.World.System.MinionsOfOmen do
  @moduledoc """
  Keeps Moonglade's watch for Omen (`Core.GameEvent.MinionsOfOmen`). An Omen
  cluster launcher reports each firework it sends up and is told when to call
  Omen; it then reports his summon events back. This process drives the
  Minions of Omen event from the watch, rests Omen after he falls, and lets
  the minions go when he leaves the world, which it also learns by
  monitoring him in case his launcher is gone first. A call Omen never
  answers is let go after ten seconds.
  """
  use GenServer

  alias ThistleTea.Game.Core.GameEvent.MinionsOfOmen
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.System.GameEvent

  @arrival_ms 10_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def launched(server \\ __MODULE__), do: GenServer.call(server, :launched)

  def omen_arrived(guid, server \\ __MODULE__) when is_integer(guid), do: GenServer.cast(server, {:omen_arrived, guid})

  def omen_fell(server \\ __MODULE__), do: GenServer.cast(server, :omen_fell)

  def omen_gone(server \\ __MODULE__), do: GenServer.cast(server, :omen_gone)

  @impl GenServer
  def init(opts) do
    state = %{
      watch: %MinionsOfOmen{},
      game_events: Keyword.get(opts, :game_events, GameEvent),
      now: Keyword.get(opts, :now, &Time.now/0),
      arrival_ms: Keyword.get(opts, :arrival_ms, @arrival_ms),
      calling: nil,
      omen: nil
    }

    {:ok, drive(state)}
  end

  @impl GenServer
  def handle_call(:launched, _from, state) do
    {watch, call_omen?} = MinionsOfOmen.launched(state.watch, state.now.())
    state = if call_omen?, do: await_arrival(state), else: state
    {:reply, call_omen?, drive(%{state | watch: watch})}
  end

  @impl GenServer
  def handle_cast({:omen_arrived, guid}, state) do
    state = %{forget_omen(state) | calling: nil}

    case Entity.pid(guid) do
      pid when is_pid(pid) -> {:noreply, %{state | omen: Process.monitor(pid)}}
      nil -> {:noreply, drive(%{state | watch: MinionsOfOmen.gone(state.watch)})}
    end
  end

  def handle_cast(:omen_fell, state) do
    {:noreply, %{state | watch: MinionsOfOmen.fell(state.watch, state.now.())}}
  end

  def handle_cast(:omen_gone, state) do
    {:noreply, state |> forget_omen() |> gone()}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{omen: ref} = state) do
    {:noreply, gone(%{state | omen: nil})}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  def handle_info({:omen_overdue, call}, %{calling: call} = state) do
    {:noreply, %{state | calling: nil, watch: MinionsOfOmen.missed(state.watch)}}
  end

  def handle_info({:omen_overdue, _call}, state), do: {:noreply, state}

  defp await_arrival(state) do
    call = make_ref()
    Process.send_after(self(), {:omen_overdue, call}, state.arrival_ms)
    %{state | calling: call}
  end

  defp gone(state), do: drive(%{state | watch: MinionsOfOmen.gone(state.watch)})

  defp forget_omen(%{omen: ref} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    %{state | omen: nil}
  end

  defp forget_omen(state), do: state

  defp drive(state) do
    :ok = GameEvent.drive(MinionsOfOmen.driven(state.watch), state.game_events)
    state
  end
end
