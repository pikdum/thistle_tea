defmodule ThistleTea.Game.World.Loader.PageText do
  @moduledoc """
  Preloaded page_text rows for readable items and objects: each page carries its text
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
      _miss -> nil
    end
  end

  def get(_entry), do: nil

  def load_all do
    Mangos.PageText
    |> Mangos.Repo.all()
    |> Enum.each(fn page ->
      :ets.insert(__MODULE__, {page.entry, %{text: page.text, next_page: page.next_page || 0}})
    end)

    :ok
  end
end
