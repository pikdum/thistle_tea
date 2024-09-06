defmodule ThistleTea.Telemetry do
  use GenServer

  require Logger

  @telemetry_interval 30_000

  def start_link(initial) do
    GenServer.start_link(__MODULE__, initial)
  end

  def handle_event(
        [:thistle_tea, :handle_packet, :stop],
        %{duration: duration},
        %{opcode: opcode},
        _config
      ) do
    :ets.insert(:telemetry, {:handle_packet, opcode, duration})
  end

  def handle_event(
        [:thistle_tea, :mob, :wake_up],
        _measurements,
        _metadata,
        _config
      ) do
    :ets.update_counter(:telemetry_counters, :active_mobs, 1)
  end

  def handle_event(
        [:thistle_tea, :mob, :try_sleep],
        _measurements,
        _metadata,
        _config
      ) do
    :ets.update_counter(:telemetry_counters, :active_mobs, -1)
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  @impl GenServer
  def init(_initial) do
    :ets.new(:telemetry, [:duplicate_bag, :named_table, :public, {:write_concurrency, :auto}])
    :ets.new(:telemetry_counters, [:set, :named_table, :public, {:write_concurrency, :auto}])
    :ets.insert(:telemetry_counters, {:active_mobs, 0})
    Process.send_after(self(), :summarize_data, @telemetry_interval)
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:summarize_data, state) do
    packet_data =
      :ets.match_object(:telemetry, {:handle_packet, :_, :_})
      |> Enum.group_by(&elem(&1, 1), &elem(&1, 2))
      |> Enum.map(fn {k, v} ->
        %{
          opcode: ThistleTea.Opcodes.get(k),
          max_duration: Enum.max(v) |> System.convert_time_unit(:native, :microsecond),
          count: Enum.count(v)
        }
      end)
      |> Enum.sort(&(Map.get(&1, :max_duration) > Map.get(&2, :max_duration)))

    if Enum.count(packet_data) > 0 do
      Logger.info("Packets: #{inspect(packet_data, pretty: true)}")
    end

    active_mobs = :ets.lookup_element(:telemetry_counters, :active_mobs, 2)

    if active_mobs > 0 do
      Logger.info("Active Mobs: #{active_mobs}")
    end

    :ets.match_delete(:telemetry, {:handle_packet, :_, :_})
    Process.send_after(self(), :summarize_data, @telemetry_interval)
    {:noreply, state}
  end
end
