defmodule ThistleTea.Telemetry.Runtime do
  @moduledoc "On-demand VM and owner-process samples for benchmark reports."

  def sample do
    {reductions, _since_last_call} = :erlang.statistics(:reductions)
    {collections, reclaimed_words, _} = :erlang.statistics(:garbage_collection)

    %{
      reductions: reductions,
      gc_collections: collections,
      gc_reclaimed_words: reclaimed_words,
      run_queue: :erlang.statistics(:run_queue),
      process_count: :erlang.system_info(:process_count),
      memory_bytes: :erlang.memory(:total),
      entities: Map.new([:players, :mobs, :game_objects], &{&1, table_size(&1)})
    }
  end

  def owners(pids) do
    samples = Enum.flat_map(pids, &owner/1)
    queues = Enum.map(samples, & &1.queue)

    %{
      count: length(samples),
      queue_total: Enum.sum(queues),
      queue_max: Enum.max(queues, fn -> 0 end),
      queue_p95: percentile(queues, 0.95),
      queue_p99: percentile(queues, 0.99),
      reductions: Enum.sum(Enum.map(samples, & &1.reductions)),
      minor_gcs: Enum.sum(Enum.map(samples, & &1.minor_gcs)),
      memory_bytes: Enum.sum(Enum.map(samples, & &1.memory))
    }
  end

  def delta(current, nil), do: current

  def delta(current, previous) do
    Enum.reduce([:reductions, :gc_collections, :gc_reclaimed_words], current, fn field, current ->
      Map.update!(current, field, &(&1 - Map.fetch!(previous, field)))
    end)
  end

  defp table_size(table) do
    case :ets.info(table, :size) do
      :undefined -> 0
      size -> size
    end
  end

  defp owner(pid) do
    case Process.info(pid, [:message_queue_len, :reductions, :garbage_collection, :memory]) do
      nil ->
        []

      info ->
        [
          %{
            queue: info[:message_queue_len],
            reductions: info[:reductions],
            memory: info[:memory],
            minor_gcs: Keyword.get(info[:garbage_collection], :minor_gcs, 0)
          }
        ]
    end
  end

  defp percentile([], _fraction), do: 0
  defp percentile(values, fraction), do: values |> Enum.sort() |> Enum.at(ceil(length(values) * fraction) - 1)
end
