defmodule ThistleTea.Game.World.Loader.PetName do
  @moduledoc """
  Startup cache of the name halves that warlock demons draw from. Every
  summon picks one opening and one closing half for its creature entry,
  as vmangos `GeneratePetName` does; entries without both halves keep their
  template name.
  """

  alias ThistleTea.DB.Mangos

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :public, read_concurrency: true])
      _ -> table
    end
  end

  def load_all(table \\ __MODULE__) do
    Mangos.PetNameGeneration
    |> Mangos.Repo.all()
    |> Enum.group_by(& &1.entry)
    |> Enum.each(fn {entry, rows} -> put(entry, halves(rows, 0), halves(rows, 1), table) end)
  end

  def put(entry, openings, closings, table \\ __MODULE__) when is_list(openings) and is_list(closings) do
    :ets.insert(table, {entry, List.to_tuple(openings), List.to_tuple(closings)})
    :ok
  end

  def generate(entry, pick \\ &:rand.uniform/1, table \\ __MODULE__) do
    case :ets.lookup(table, entry) do
      [{^entry, openings, closings}] when tuple_size(openings) > 0 and tuple_size(closings) > 0 ->
        draw(openings, pick) <> draw(closings, pick)

      _ ->
        nil
    end
  end

  defp draw(words, pick), do: elem(words, pick.(tuple_size(words)) - 1)

  defp halves(rows, half), do: for(%{half: ^half, word: word} <- rows, do: word)
end
