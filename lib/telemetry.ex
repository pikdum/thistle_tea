defmodule ThistleTea.Telemetry do
  use GenServer

  require Logger

  @telemetry_interval 60_000

  def start_link(initial) do
    GenServer.start_link(__MODULE__, initial)
  end

  def handle_event([:thistle_tea, :handle_packet, :stop], measurements, metadata, _config) do
    :ets.insert(:telemetry, {metadata.opcode, measurements.duration})
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  @impl GenServer
  def init(_initial) do
    :ets.new(:telemetry, [:duplicate_bag, :named_table, :public, {:write_concurrency, :auto}])
    Process.send_after(self(), :summarize_data, @telemetry_interval)
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:summarize_data, state) do
    data =
      :ets.tab2list(:telemetry)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {k, v} ->
        %{
          opcode: ThistleTea.Opcodes.get(k),
          max_duration: Enum.max(v) |> System.convert_time_unit(:native, :microsecond),
          count: Enum.count(v)
        }
      end)
      |> Enum.sort(&(Map.get(&1, :max_duration) > Map.get(&2, :max_duration)))

    if Enum.count(data) > 0 do
      Logger.info("Telemetry: #{inspect(data, pretty: true)}")
    end

    :ets.delete_all_objects(:telemetry)
    Process.send_after(self(), :summarize_data, @telemetry_interval)
    {:noreply, state}
  end
end
