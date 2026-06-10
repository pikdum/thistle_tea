defmodule ThistleTea.Game.World.Loader.Item do
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.ItemTemplate

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def get_template(entry) when is_integer(entry) and entry > 0 do
    case :ets.lookup(__MODULE__, entry) do
      [{^entry, %ItemTemplate{} = template}] -> template
      _ -> load_template(entry)
    end
  end

  def get_template(_entry), do: nil

  def random_template_by_inventory_type(inventory_type) do
    case Mangos.ItemTemplate.random_by_type(inventory_type) do
      %Mangos.ItemTemplate{} = row -> cache(ItemTemplate.build(row))
      _ -> nil
    end
  end

  def random_equipment do
    %{
      head: random_template_by_inventory_type(1),
      neck: random_template_by_inventory_type(2),
      shoulders: random_template_by_inventory_type(3),
      body: random_template_by_inventory_type(4),
      chest: random_template_by_inventory_type(5),
      waist: random_template_by_inventory_type(6),
      legs: random_template_by_inventory_type(7),
      feet: random_template_by_inventory_type(8),
      wrists: random_template_by_inventory_type(9),
      hands: random_template_by_inventory_type(10),
      finger1: random_template_by_inventory_type(11),
      finger2: random_template_by_inventory_type(11),
      trinket1: random_template_by_inventory_type(12),
      trinket2: random_template_by_inventory_type(12),
      back: random_template_by_inventory_type(16),
      mainhand: random_template_by_inventory_type(13),
      offhand: random_template_by_inventory_type(13),
      tabard: random_template_by_inventory_type(19)
    }
  end

  defp load_template(entry) do
    case Mangos.Repo.get(Mangos.ItemTemplate, entry) do
      %Mangos.ItemTemplate{} = row -> cache(ItemTemplate.build(row))
      _ -> nil
    end
  end

  defp cache(%ItemTemplate{entry: entry} = template) do
    :ets.insert(__MODULE__, {entry, template})
    template
  end
end
