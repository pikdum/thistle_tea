defmodule ThistleTea.TelemetryTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Telemetry
  alias ThistleTea.Telemetry.Runtime

  describe "start_link/1" do
    test "reattaches collection after the supervised owner restarts" do
      before = Telemetry.checkpoint()
      :ok = Supervisor.terminate_child(ThistleTea.Supervisor, Telemetry)
      {:ok, pid} = Supervisor.restart_child(ThistleTea.Supervisor, Telemetry)
      assert pid != before.epoch
      tick(10)

      report = Telemetry.report(before)
      assert report.elapsed_ms == nil
      assert Enum.any?(report.durations, &(&1.name == :mob_tick and &1.label == :success and &1.count == 1))
    end
  end

  describe "report/2" do
    test "reports window quantiles without deleting earlier measurements" do
      before = Telemetry.checkpoint()
      Enum.each(1..100, fn n -> tick(if(n > 95, do: 1_000, else: 10)) end)
      first = Telemetry.checkpoint()
      report = Telemetry.report(before, first)
      metric = Enum.find(report.durations, &(&1.name == :mob_tick and &1.label == :success))
      assert metric.count == 100
      assert metric.mean_us == 59.5
      assert metric.p95_us_upper_bound == 16
      assert metric.p99_us_upper_bound == 1_024
      assert metric.max_us_upper_bound == 1_024
      tick(1)
      second = Telemetry.report(first)
      assert Enum.find(second.durations, &(&1.name == :mob_tick and &1.label == :success)).count == 1

      assert Enum.find(Telemetry.report(before).durations, &(&1.name == :mob_tick and &1.label == :success)).count ==
               101
    end

    test "keeps histogram storage bounded under concurrent writers" do
      tick(1)
      before = Telemetry.checkpoint()
      key = {:duration, :mob_tick, :success}
      size = tuple_size(Map.fetch!(before.rows, key))

      1..8
      |> Task.async_stream(fn _ -> Enum.each(1..1_000, fn _ -> tick(10) end) end, ordered: false)
      |> Enum.each(fn result -> assert result == {:ok, :ok} end)

      current = Telemetry.checkpoint()
      metric = Enum.find(Telemetry.report(before, current).durations, &(&1.name == :mob_tick and &1.label == :success))
      assert metric.count == 8_000
      assert metric.mean_us == 10
      assert tuple_size(Map.fetch!(current.rows, key)) == size
    end

    test "coalesces arbitrary behavior statuses into one histogram" do
      before = Telemetry.checkpoint()

      Enum.each(1..100, fn status ->
        :telemetry.execute([:thistle_tea, :mob, :ai_tick], %{duration: 0}, %{status: status})
      end)

      metrics = Enum.filter(Telemetry.report(before).durations, &(&1.name == :mob_tick))
      assert [%{label: :unknown, count: 100}] = metrics
    end

    test "counts successful wire bytes and failures separately" do
      before = Telemetry.checkpoint()
      :telemetry.execute([:thistle_tea, :network, :send], %{bytes: 42, uncompressed_bytes: 100}, %{result: :ok})

      :telemetry.execute([:thistle_tea, :network, :send], %{bytes: 42, uncompressed_bytes: 100}, %{
        result: {:error, :closed}
      })

      report = Telemetry.report(before)
      assert report.counters.wire_packets == 1
      assert report.counters.wire_bytes == 42
      assert report.counters.uncompressed_bytes == 100
      assert report.counters.wire_failures == 1
    end

    test "rejects previous checkpoints from another collector lifetime" do
      before = %{Telemetry.checkpoint() | epoch: self()}
      tick(1)
      assert Telemetry.report(before).elapsed_ms == nil
    end
  end

  describe "owners/1" do
    test "samples mailbox pressure and ignores terminated owners" do
      dead = spawn(fn -> :ok end)
      monitor = Process.monitor(dead)
      assert_receive {:DOWN, ^monitor, :process, ^dead, _}
      send(self(), :queued)
      sample = Runtime.owners([self(), dead])
      assert sample.count == 1
      assert sample.queue_total >= 1
      assert sample.queue_p99 >= 1
      assert sample.reductions > 0
      assert_receive :queued
    end
  end

  defp tick(microseconds) do
    :telemetry.execute(
      [:thistle_tea, :mob, :ai_tick],
      %{duration: System.convert_time_unit(microseconds, :microsecond, :native)},
      %{status: :success}
    )
  end
end
