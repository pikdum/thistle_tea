defmodule ThistleTea.Game.World.Loader.QuestGreeting do
  @moduledoc """
  Startup cache of the greetings quest givers speak above a list of
  several quests, keyed by creature or game object entry the way vmangos
  `quest_greeting` types them.
  """

  alias ThistleTea.DB.Mangos

  defmodule Greeting do
    @moduledoc false
    defstruct text: "", emote: 0, emote_delay: 0
  end

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, read_concurrency: true])
      _ -> table
    end
  end

  def load_all(table \\ __MODULE__) do
    Mangos.QuestGreeting
    |> Mangos.Repo.all()
    |> Enum.filter(&(&1.type in [0, 1]))
    |> Enum.each(fn row ->
      greeting = %Greeting{text: row.content_default, emote: row.emote_id, emote_delay: row.emote_delay}
      put(source(row.type), row.entry, greeting, table)
    end)
  end

  def put(source, entry, %Greeting{} = greeting, table \\ __MODULE__) when source in [:unit, :game_object] do
    :ets.insert(table, {{source, entry}, greeting})
    :ok
  end

  def get(source, entry, table \\ __MODULE__) do
    case :ets.lookup(table, {source, entry}) do
      [{_key, %Greeting{} = greeting}] -> greeting
      [] -> nil
    end
  end

  defp source(0), do: :unit
  defp source(1), do: :game_object
end
