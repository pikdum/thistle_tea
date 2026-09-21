defmodule ThistleTea.Game.World.Loader.GameObjectTemplate do
  @moduledoc """
  ETS cache of slim gameobject-template query info, preloaded at boot so
  gameplay queries answer from running state instead of the Mangos seed.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Spell.Focus
  alias ThistleTea.Game.World.Loader.Faction

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    bounds =
      Mangos.GameObjectDisplayInfoAddon
      |> Mangos.Repo.all()
      |> Map.new(fn row ->
        {row.display_id, {{row.min_x, row.min_y, row.min_z}, {row.max_x, row.max_y, row.max_z}}}
      end)

    Mangos.GameObjectTemplate
    |> Mangos.Repo.all()
    |> Enum.each(&cache(&1, Map.get(bounds, &1.display_id)))
  end

  def get(entry) when is_integer(entry) and entry > 0 do
    case :ets.lookup(__MODULE__, entry) do
      [{^entry, %GameObjectTemplate{} = template}] -> template
      _ -> load(entry)
    end
  end

  def get(_entry), do: nil

  def cached(entry) when is_integer(entry) and entry > 0 do
    case :ets.lookup(__MODULE__, entry) do
      [{^entry, %GameObjectTemplate{} = template}] -> template
      _missing -> nil
    end
  end

  def cached(_entry), do: nil

  def put(%GameObjectTemplate{} = template) do
    :ets.insert(__MODULE__, {template.entry, template})

    case Focus.definition(template) do
      {id, radius} -> :ets.insert(__MODULE__, {{:focus_radius, id}, max(radius, focus_radius(id))})
      nil -> :ok
    end

    template
  end

  def focus_radius(id) do
    case :ets.lookup(__MODULE__, {:focus_radius, id}) do
      [{_key, radius}] -> radius
      [] -> 0
    end
  end

  defp load(entry) do
    case Mangos.Repo.get(Mangos.GameObjectTemplate, entry) do
      %Mangos.GameObjectTemplate{} = row -> cache(row, load_bounds(row.display_id))
      _ -> nil
    end
  end

  defp load_bounds(display_id) do
    case Mangos.Repo.get(Mangos.GameObjectDisplayInfoAddon, display_id) do
      nil -> nil
      row -> {{row.min_x, row.min_y, row.min_z}, {row.max_x, row.max_y, row.max_z}}
    end
  end

  defp cache(%Mangos.GameObjectTemplate{} = row, bounds) do
    Faction.metadata(row.faction)
    template = GameObjectTemplate.build(row)
    template = %{template | bounds: bounds}
    put(template)
  end
end
