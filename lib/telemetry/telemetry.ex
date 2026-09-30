defmodule ThistleTea.Telemetry do
  @moduledoc """
  Bounded cumulative gameplay metrics. Each duration updates one fixed-size
  histogram atomically; reports subtract checkpoints without deleting samples.
  Quantiles are bucket upper bounds in microseconds, rather than exact samples.
  Runtime and owner sampling is explicit and stays out of gameplay hot loops.
  """
  use Boundary, deps: []
  use GenServer

  alias ThistleTea.Telemetry.Runtime

  require Logger

  @bounds Enum.map(0..24, &Integer.pow(2, &1)) ++ [:infinity]
  @bucket_count length(@bounds)
  @empty_histogram List.to_tuple([nil, 0, 0 | List.duplicate(0, @bucket_count)])
  @events [
    [:thistle_tea, :handle_packet, :stop],
    [:thistle_tea, :mob, :ai_tick],
    [:thistle_tea, :player, :tick],
    [:thistle_tea, :mob, :wake_up],
    [:thistle_tea, :mob, :try_sleep],
    [:thistle_tea, :network, :send],
    [:thistle_tea, :proximity, :check]
  ]

  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)

  def checkpoint do
    %{
      at: System.monotonic_time(:millisecond),
      epoch: :ets.info(__MODULE__, :owner),
      rows: Map.new(:ets.tab2list(__MODULE__), &{elem(&1, 0), &1}),
      runtime: Runtime.sample()
    }
  end

  def report(previous \\ nil, current \\ checkpoint()) do
    previous = if previous && previous.epoch == current.epoch, do: previous, else: %{at: nil, rows: %{}, runtime: nil}

    histograms =
      for {{:duration, name, label} = key, row} <- current.rows, do: histogram(key, row, previous.rows, name, label)

    counters =
      for {{:counter, name} = key, {_, value}} <- current.rows,
          into: %{},
          do: {name, value - elem(Map.get(previous.rows, key, {key, 0}), 1)}

    %{
      elapsed_ms: if(previous.at, do: current.at - previous.at),
      durations: Enum.filter(histograms, &(&1.count > 0)),
      counters: counters,
      runtime: Runtime.delta(current.runtime, previous.runtime),
      storage_rows: :ets.info(__MODULE__, :size),
      storage_bytes: :ets.info(__MODULE__, :memory) * :erlang.system_info(:wordsize)
    }
  end

  def handle_event([:thistle_tea, :handle_packet, :stop], %{duration: duration}, %{opcode: opcode}, _config)
      when is_integer(opcode) and opcode in 0..0xFFFF, do: duration(:packet, opcode, duration)

  def handle_event([:thistle_tea, :mob, :ai_tick], %{duration: duration}, metadata, _config) do
    status = Map.get(metadata, :status)
    label = if status in [:running, :success, :failure], do: status, else: :unknown
    duration(:mob_tick, label, duration)
  end

  def handle_event([:thistle_tea, :player, :tick], %{duration: duration}, _metadata, _config),
    do: duration(:player_tick, :all, duration)

  def handle_event([:thistle_tea, :mob, :wake_up], _measurements, _metadata, _config), do: counter(:mob_wakeups, 1)
  def handle_event([:thistle_tea, :mob, :try_sleep], _measurements, _metadata, _config), do: counter(:mob_sleeps, 1)

  def handle_event([:thistle_tea, :network, :send], measurements, %{result: :ok}, _config) do
    counter(:wire_packets, 1)
    counter(:wire_bytes, measurements.bytes)
    counter(:uncompressed_bytes, measurements.uncompressed_bytes)
  end

  def handle_event([:thistle_tea, :network, :send], _measurements, _metadata, _config), do: counter(:wire_failures, 1)

  def handle_event([:thistle_tea, :proximity, :check], _measurements, %{action: action}, _config)
      when action in [:scheduled, :cancelled, :fired, :stale, :coalesced], do: counter(action, 1)

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  @impl GenServer
  def init(options) do
    :ets.new(__MODULE__, [:named_table, :public, write_concurrency: :auto])
    :telemetry.detach(__MODULE__)
    :ok = :telemetry.attach_many(__MODULE__, @events, &__MODULE__.handle_event/4, nil)
    interval = Keyword.get(options, :interval, 30_000)
    if interval, do: Process.send_after(self(), :report, interval)
    {:ok, %{interval: interval, previous: checkpoint()}}
  end

  @impl GenServer
  def handle_info(:report, state) do
    current = checkpoint()

    if state.interval do
      Logger.info("Gameplay metrics: #{inspect(report(state.previous, current))}")
      Process.send_after(self(), :report, state.interval)
    end

    {:noreply, %{state | previous: current}}
  end

  @impl GenServer
  def terminate(_reason, _state), do: :telemetry.detach(__MODULE__)

  defp duration(name, label, duration) do
    value = max(System.convert_time_unit(duration, :native, :microsecond), 0)
    bucket = Enum.find_index(@bounds, &(&1 == :infinity or value <= &1))
    key = {:duration, name, label}
    initial = put_elem(@empty_histogram, 0, key)
    :ets.update_counter(__MODULE__, key, [{2, 1}, {3, value}, {4 + bucket, 1}], initial)
    :ok
  end

  defp counter(name, amount) do
    key = {:counter, name}
    :ets.update_counter(__MODULE__, key, {2, amount}, {key, 0})
    :ok
  end

  defp histogram(key, row, previous, name, label) do
    before = Map.get(previous, key, List.to_tuple(List.duplicate(0, tuple_size(row))))
    values = for index <- 1..(tuple_size(row) - 1), do: elem(row, index) - elem(before, index)
    [count, sum | buckets] = values

    %{
      name: name,
      label: label,
      count: count,
      mean_us: if(count > 0, do: sum / count, else: 0),
      p95_us_upper_bound: quantile(buckets, count, 0.95),
      p99_us_upper_bound: quantile(buckets, count, 0.99),
      max_us_upper_bound: quantile(buckets, count, 1.0)
    }
  end

  defp quantile(_buckets, 0, _fraction), do: 0

  defp quantile(buckets, count, fraction) do
    target = ceil(count * fraction)

    buckets
    |> Enum.zip(@bounds)
    |> Enum.reduce_while(0, fn {n, bound}, seen ->
      if seen + n >= target, do: {:halt, bound}, else: {:cont, seen + n}
    end)
  end
end
