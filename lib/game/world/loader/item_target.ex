defmodule ThistleTea.Game.World.Loader.ItemTarget do
  @moduledoc """
  Preloads creature entry and life-state restrictions for on-use items.
  Multiple targets for an item are alternatives.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    from(target in Mangos.ItemRequiredTarget,
      join: item in Mangos.ItemTemplate,
      on: item.entry == target.entry,
      join: creature in Mangos.CreatureTemplate,
      on: creature.entry == target.target_entry,
      where: target.type in [1, 2],
      select: {target.entry, target.target_entry, target.type},
      distinct: true,
      order_by: [target.entry, target.target_entry, target.type]
    )
    |> Mangos.Repo.all()
    |> Enum.group_by(fn {item, _entry, _type} -> item end, fn {_item, entry, type} -> {entry, type == 1} end)
    |> Enum.each(fn row -> :ets.insert(__MODULE__, row) end)

    :ok
  end

  def get(entry) do
    case :ets.lookup(__MODULE__, entry) do
      [{^entry, targets}] -> targets
      [] -> []
    end
  end
end
