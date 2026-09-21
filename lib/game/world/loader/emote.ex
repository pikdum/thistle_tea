defmodule ThistleTea.Game.World.Loader.Emote do
  @moduledoc """
  Startup cache of vanilla animation definitions and text-emote mappings.
  """

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Emote

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, read_concurrency: true])
      _table -> table
    end
  end

  def load_all(table \\ __MODULE__), do: load(DBC.all(Emotes), DBC.all(EmotesText), table)

  def load(animations, texts, table \\ __MODULE__) do
    for row <- animations do
      :ets.insert(table, {{:animation, row.id}, %Emote{id: row.id, persistent?: row.spec_proc != 0}})
    end

    for row <- texts do
      :ets.insert(table, {{:text, row.id}, row.emote})
    end

    :ok
  end

  def animation(id, table \\ __MODULE__), do: lookup(table, {:animation, id})

  def text(id, table \\ __MODULE__) do
    case lookup(table, {:text, id}) do
      animation_id when is_integer(animation_id) -> animation(animation_id, table)
      _ -> nil
    end
  end

  defp lookup(table, key) do
    case :ets.lookup(table, key) do
      [{^key, value}] -> value
      _ -> nil
    end
  end
end
