defmodule ThistleTea.Game.World.Loader.Durability do
  @moduledoc """
  Startup cache of client durability repair multipliers by item level,
  class, subclass, and quality. Repair requests never query the database.
  """

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Durability, as: DurabilityLogic

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, read_concurrency: true])
      _table -> table
    end
  end

  def load_all(table \\ __MODULE__) do
    for row <- DBC.all(DurabilityCosts),
        {class, prefix, subclasses} <- [{2, "weapon", 0..20}, {4, "armour", 0..7}],
        subclass <- subclasses do
      :ets.insert(table, {{row.id, class, subclass}, Map.fetch!(row, :"#{prefix}_subclass_cost_#{subclass}")})
    end

    for row <- DBC.all(DurabilityQuality), do: :ets.insert(table, {{:quality, row.id}, row.data})
    :ok
  end

  def cost(%Item{} = item, discount \\ 1.0, table \\ __MODULE__) do
    with {level, class, subclass, quality_id} <- DurabilityLogic.cost_key(Item.template(item)),
         [{_key, multiplier}] <- :ets.lookup(table, {level, class, subclass}),
         [{_key, quality}] <- :ets.lookup(table, {:quality, quality_id}) do
      DurabilityLogic.repair_cost(item, multiplier, quality, discount)
    else
      _missing -> nil
    end
  end

  def sale_penalty(%Item{item: component} = item, table \\ __MODULE__) do
    lost = max((component.max_durability || 0) - (component.durability || 0), 0)

    if lost > 0 do
      cost(item, 1.0, table)
    else
      0
    end
  end
end
