defmodule ThistleTea.Game.World.Loader.Item do
  @moduledoc """
  ETS cache of item templates from Mangos, plus random-equipment picks for
  generated characters.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Proficiency

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]
  @random_candidates 50

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def get_template(entry) when is_integer(entry) and entry > 0 do
    case get_cached_template(entry) do
      %ItemTemplate{} = template -> template
      _ -> load_template(entry)
    end
  end

  def get_template(_entry), do: nil

  def get_cached_template(entry) when is_integer(entry) and entry > 0 do
    case :ets.lookup(__MODULE__, entry) do
      [{^entry, %ItemTemplate{} = template}] -> template
      _ -> nil
    end
  end

  def get_cached_template(_entry), do: nil

  def random_usable_template(inventory_type, race, class, level, prof \\ Proficiency.all()) do
    inventory_type
    |> Mangos.ItemTemplate.random_usable_by_type(race, class, level, @random_candidates)
    |> Enum.map(&ItemTemplate.build/1)
    |> Enum.find(&(Proficiency.can_equip?(prof, &1) == :ok))
    |> case do
      %ItemTemplate{} = template -> cache(template)
      _none -> nil
    end
  end

  def random_equipment(race, class, level, prof \\ Proficiency.all()) do
    random = fn inventory_type -> random_usable_template(inventory_type, race, class, level, prof) end

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
      mainhand: random.(13) || random.(17),
      offhand: random_offhand(random, prof),
      tabard: random.(19)
    }
  end

  defp random_offhand(random, %Proficiency{dual_wield?: true}), do: random.(13)
  defp random_offhand(random, %Proficiency{}), do: random.(14) || random.(23)

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
