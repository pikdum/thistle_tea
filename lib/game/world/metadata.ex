defmodule ThistleTea.Game.World.Metadata do
  @moduledoc """
  ETS map of per-guid metadata (name, faction, flags, …) readable without
  calling into the owning process.
  """
  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    if is_atom(table) do
      case :ets.whereis(table) do
        :undefined ->
          :ets.new(table, @table_options)

        _table_id ->
          table
      end
    else
      table
    end
  end

  def put(table \\ __MODULE__, guid, metadata) do
    :ets.insert(table, {guid, normalize_metadata(metadata)})
    :ok
  end

  def update(table \\ __MODULE__, guid, metadata) do
    metadata = normalize_metadata(metadata)

    case get(table, guid) do
      nil ->
        if :ets.insert_new(table, {guid, metadata}), do: :ok, else: update(table, guid, metadata)

      current ->
        if replace(table, guid, current, Map.merge(current, metadata)),
          do: :ok,
          else: update(table, guid, metadata)
    end
  end

  def get(table \\ __MODULE__, guid) do
    case :ets.lookup(table, guid) do
      [{^guid, data}] -> data
      _ -> nil
    end
  end

  def query(table \\ __MODULE__, guid, keys)

  def query(table, guid, keys) when is_list(keys) do
    case get(table, guid) do
      nil -> nil
      data -> Map.take(data, keys)
    end
  end

  def query(table, guid, _keys), do: get(table, guid)

  def delete(table \\ __MODULE__, guid) do
    :ets.delete(table, guid)
    :ok
  end

  def increment(guid, key), do: update_counter(__MODULE__, guid, key, 1, nil)

  def increment(table, guid, key) when is_atom(table) or is_reference(table) do
    update_counter(table, guid, key, 1, nil)
  end

  def increment(guid, key, max) do
    update_counter(__MODULE__, guid, key, 1, max)
  end

  def increment(table, guid, key, max) when is_atom(table) or is_reference(table) do
    update_counter(table, guid, key, 1, max)
  end

  def decrement(guid, key), do: update_counter(__MODULE__, guid, key, -1, nil)

  def decrement(table, guid, key) when is_atom(table) or is_reference(table) do
    update_counter(table, guid, key, -1, nil)
  end

  def decrement(guid, key, min) do
    update_counter(__MODULE__, guid, key, -1, min)
  end

  def decrement(table, guid, key, min) when is_atom(table) or is_reference(table) do
    update_counter(table, guid, key, -1, min)
  end

  def find_guid_by(table \\ __MODULE__, key, value) do
    :ets.foldl(
      fn {guid, data}, acc ->
        if acc == nil and Map.get(data, key) == value do
          guid
        else
          acc
        end
      end,
      nil,
      table
    )
  end

  defp update_counter(table, guid, key, delta, bound) do
    case get(table, guid) do
      nil ->
        0

      current ->
        value = Map.get(current, key, 0)
        value = if is_number(value), do: value, else: 0
        updated = apply_bound(value + delta, delta, bound)

        if replace(table, guid, current, Map.put(current, key, updated)),
          do: updated,
          else: update_counter(table, guid, key, delta, bound)
    end
  end

  defp replace(table, guid, current, updated) do
    :ets.select_replace(table, [{{guid, :"$1"}, [{:"=:=", :"$1", {:const, current}}], [{{guid, {:const, updated}}}]}]) ==
      1
  end

  defp apply_bound(value, delta, bound) when is_number(bound) do
    cond do
      delta > 0 -> min(value, bound)
      delta < 0 -> max(value, bound)
      true -> value
    end
  end

  defp apply_bound(value, _delta, _bound), do: value

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(metadata) when is_list(metadata), do: Map.new(metadata)
  defp normalize_metadata(_metadata), do: %{}
end
