defmodule ThistleTea.Game.World.Loader.Condition do
  @moduledoc """
  Loads `conditions` rows referenced by AI events and script steps into
  resolved `Data.Condition` trees, recursively fetching combinator children so
  the runtime evaluator never touches the database. Missing or cyclic
  references resolve to `nil` children, which marks the parent unsupported.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Condition

  def load_by_ids([]), do: %{}

  def load_by_ids(entries) when is_list(entries) do
    entries = entries |> Enum.filter(&(is_integer(&1) and &1 > 0)) |> Enum.uniq()
    rows_by_entry = fetch_rows(entries, %{})
    Map.new(entries, fn entry -> {entry, build_tree(entry, rows_by_entry, MapSet.new())} end)
  end

  defp fetch_rows([], rows_by_entry), do: rows_by_entry

  defp fetch_rows(entries, rows_by_entry) do
    rows = entries |> Mangos.Condition.query() |> Mangos.Repo.all()
    rows_by_entry = Enum.into(rows, rows_by_entry, fn row -> {row.condition_entry, row} end)

    rows
    |> Enum.flat_map(&Condition.combinator_child_entries/1)
    |> Enum.uniq()
    |> Enum.reject(&Map.has_key?(rows_by_entry, &1))
    |> fetch_rows(rows_by_entry)
  end

  defp build_tree(entry, rows_by_entry, visited) do
    with false <- MapSet.member?(visited, entry),
         %Mangos.Condition{} = row <- Map.get(rows_by_entry, entry) do
      visited = MapSet.put(visited, entry)

      children =
        row
        |> Condition.combinator_child_entries()
        |> Enum.map(&build_tree(&1, rows_by_entry, visited))

      Condition.build(row, children)
    else
      _ -> nil
    end
  end
end
