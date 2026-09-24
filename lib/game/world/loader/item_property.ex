defmodule ThistleTea.Game.World.Loader.ItemProperty do
  @moduledoc "Preloads item-property definitions and patch-appropriate weighted selection tables."
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.ItemProperty
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.ItemProperties

  @supported_patch 10
  @table_options [:named_table, :public, read_concurrency: true]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    load_definitions()
    load_tables()
  end

  def load_definitions do
    DBC.all(ItemRandomProperties)
    |> Enum.each(fn row ->
      property = %ItemProperty{
        id: row.id,
        suffix: row.suffix_en_gb,
        enchantments: [row.spell_item_enchantment_0, row.spell_item_enchantment_1, row.spell_item_enchantment_2]
      }

      :ets.insert(__MODULE__, {{:property, row.id}, property})
    end)
  end

  def load_tables do
    Mangos.ItemEnchantmentTemplate
    |> where([row], row.patch_min <= @supported_patch and row.patch_max >= @supported_patch)
    |> order_by([row], [row.entry, row.ench])
    |> Mangos.Repo.all()
    |> Enum.group_by(& &1.entry, &{&1.ench, &1.chance})
    |> Enum.each(fn {entry, choices} -> :ets.insert(__MODULE__, {{:table, entry}, choices}) end)
  end

  def get(id) do
    case :ets.lookup(__MODULE__, {:property, id}) do
      [{_key, %ItemProperty{} = property}] -> property
      [] -> nil
    end
  end

  def choices(entry) do
    case :ets.lookup(__MODULE__, {:table, entry}) do
      [{_key, choices}] -> choices
      [] -> []
    end
  end

  def roll(template, random \\ &:rand.uniform/0)

  def roll(%ItemTemplate{random_property: entry}, random) when is_integer(entry) and entry > 0 do
    entry |> choices() |> ItemProperties.select(random.()) |> get()
  end

  def roll(%ItemTemplate{}, _random), do: nil
end
