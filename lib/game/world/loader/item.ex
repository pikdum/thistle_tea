defmodule ThistleTea.Game.World.Loader.Item do
  @moduledoc """
  ETS cache of item templates from Mangos, plus random-equipment picks for
  generated characters.
  """
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

  def random_usable_template(inventory_type, race, class, level) do
    case Mangos.ItemTemplate.random_usable_by_type(inventory_type, race, class, level) do
      %Mangos.ItemTemplate{} = row -> cache(ItemTemplate.build(row))
      _ -> nil
    end
  end

  def random_equipment(race, class, level) do
    random = fn inventory_type -> random_usable_template(inventory_type, race, class, level) end

    %{
      head: random.(1),
      neck: random.(2),
      shoulders: random.(3),
      body: random.(4),
      chest: random.(5),
      waist: random.(6),
      legs: random.(7),
      feet: random.(8),
      wrists: random.(9),
      hands: random.(10),
      finger1: random.(11),
      finger2: random.(11),
      trinket1: random.(12),
      trinket2: random.(12),
      back: random.(16),
      mainhand: random.(13),
      offhand: random.(13),
      tabard: random.(19)
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
