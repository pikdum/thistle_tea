defmodule ThistleTea.Game.World.Metadata do
  def init(table \\ __MODULE__) do
    if is_atom(table) do
      case :ets.whereis(table) do
        :undefined ->
          :ets.new(table, [:named_table, :public, read_concurrency: true, write_concurrency: true])

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
    current =
      case :ets.lookup(table, guid) do
        [{^guid, data}] when is_map(data) -> data
        _ -> %{}
      end

    :ets.insert(table, {guid, Map.merge(current, normalize_metadata(metadata))})
    :ok
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

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(metadata) when is_list(metadata), do: Map.new(metadata)
  defp normalize_metadata(_metadata), do: %{}
end
