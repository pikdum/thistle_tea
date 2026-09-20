defmodule ThistleTea.Game.World.Loader.StableSlotPrice do
  @moduledoc """
  Startup cache of vanilla's two stable slot prices.
  """

  alias ThistleTea.DBC

  def init do
    case :ets.whereis(__MODULE__) do
      :undefined -> :ets.new(__MODULE__, [:named_table, :public, read_concurrency: true])
      table -> table
    end
  end

  def load_all do
    StableSlotPrices
    |> DBC.all()
    |> Enum.filter(&(&1.id in 1..2))
    |> Enum.each(&:ets.insert(__MODULE__, {&1.id, &1.cost}))
  end

  def cost(slot) when slot in 1..2 do
    case :ets.lookup(__MODULE__, slot) do
      [{^slot, cost}] -> cost
      _ -> nil
    end
  end

  def cost(_slot), do: nil
end
