defmodule ThistleTea.Game.World.Loader.BankBagSlotPrice do
  @moduledoc """
  Startup cache of the six bank-bag slot prices supported by build 5875.
  """

  alias ThistleTea.DBC

  @table_options [:named_table, :public, read_concurrency: true]
  @client_slots 1..6

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all(table \\ __MODULE__) do
    BankBagSlotPrices
    |> DBC.all()
    |> Enum.filter(&(&1.id in @client_slots))
    |> Enum.each(&:ets.insert(table, {&1.id, &1.cost}))

    :ok
  end

  def cost(slot, table \\ __MODULE__)

  def cost(slot, table) when slot in @client_slots do
    case :ets.lookup(table, slot) do
      [{^slot, cost}] when is_integer(cost) -> cost
      _missing -> nil
    end
  end

  def cost(_slot, _table), do: nil
end
