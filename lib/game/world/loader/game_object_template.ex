defmodule ThistleTea.Game.World.Loader.GameObjectTemplate do
  @moduledoc """
  ETS cache of slim gameobject-template query info, preloaded at boot so
  gameplay queries answer from running state instead of the Mangos seed.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    Mangos.GameObjectTemplate
    |> Mangos.Repo.all()
    |> Enum.each(&cache/1)
  end

  def get(entry) when is_integer(entry) and entry > 0 do
    case :ets.lookup(__MODULE__, entry) do
      [{^entry, %GameObjectTemplate{} = template}] -> template
      _ -> load(entry)
    end
  end

  def get(_entry), do: nil

  defp load(entry) do
    case Mangos.Repo.get(Mangos.GameObjectTemplate, entry) do
      %Mangos.GameObjectTemplate{} = row -> cache(row)
      _ -> nil
    end
  end

  defp cache(%Mangos.GameObjectTemplate{} = row) do
    template = GameObjectTemplate.build(row)
    :ets.insert(__MODULE__, {template.entry, template})
    template
  end
end
