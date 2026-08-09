defmodule ThistleTea.Game.World.Loader.BroadcastText do
  @moduledoc """
  ETS cache of broadcast text payloads used by instance-script callbacks.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.World.Loader.Script

  @table_options [:named_table, :public, read_concurrency: true]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all(entries, table \\ __MODULE__) when is_list(entries) do
    entries = Enum.uniq(entries)

    from(text in Mangos.BroadcastText, where: text.entry in ^entries)
    |> Mangos.Repo.all()
    |> Enum.each(fn row ->
      :ets.insert(table, {row.entry, build(row)})
    end)

    :ok
  end

  def get(entry, table \\ __MODULE__) when is_integer(entry) do
    case :ets.lookup(table, entry) do
      [{^entry, text}] -> text
      [] -> nil
    end
  end

  defp build(%Mangos.BroadcastText{} = row) do
    %{
      text: text(row),
      chat_type: Script.chat_type(row.chat_type),
      language: row.language_id || 0,
      emote_id: row.emote_id1 || 0
    }
  end

  defp text(%Mangos.BroadcastText{male_text: male, female_text: female}) do
    cond do
      is_binary(male) and male != "" -> male
      is_binary(female) and female != "" -> female
      true -> ""
    end
  end
end
