defmodule ThistleTea.Game.World.Loader.PageText do
  @moduledoc """
  ETS-cached page_text rows for readable items: each page carries its text
  and the next page id in the chain (0 ends the chain).
  """
  alias ThistleTea.DB.Mangos

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def get(entry) when is_integer(entry) and entry > 0 do
    case :ets.lookup(__MODULE__, entry) do
      [{^entry, page}] -> page
      _miss -> cache(entry, load(entry))
    end
  end

  def get(_entry), do: nil

  defp load(entry) do
    case Mangos.Repo.get(Mangos.PageText, entry) do
      %Mangos.PageText{text: text, next_page: next_page} -> %{text: text, next_page: next_page || 0}
      _missing -> nil
    end
  end

  defp cache(entry, page) do
    :ets.insert(__MODULE__, {entry, page})
    page
  end
end
