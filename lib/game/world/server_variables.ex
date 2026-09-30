defmodule ThistleTea.Game.World.ServerVariables do
  @moduledoc """
  Runtime server-wide script variables. Unwritten indices read as zero.
  The application owns the table so values survive entity and map lifetimes,
  but reset when the server restarts.
  """

  alias ThistleTea.Game.World.Topics

  @maximum 0xFFFFFFFF
  @table_options [:named_table, :public, read_concurrency: true]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def valid?(index, value), do: unsigned?(index) and unsigned?(value)

  def put(index, value, table \\ __MODULE__) do
    if valid?(index, value) do
      previous = get(index, table)
      true = :ets.insert(table, {index, value})

      if table == __MODULE__ and previous != value,
        do: Topics.publish(Topics.server_variable(index), {:server_variable_changed, index})

      :ok
    else
      {:error, :invalid_variable}
    end
  end

  def get(index, table \\ __MODULE__) do
    case :ets.lookup(table, index) do
      [{^index, value}] -> value
      [] -> 0
    end
  end

  def snapshot(table \\ __MODULE__), do: table |> :ets.tab2list() |> Map.new()

  defp unsigned?(value), do: is_integer(value) and value >= 0 and value <= @maximum
end
