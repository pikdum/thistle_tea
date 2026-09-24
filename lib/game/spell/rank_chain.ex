defmodule ThistleTea.Game.Spell.RankChain do
  @moduledoc "Builds rank lineages from the successor links in skill abilities."

  def from_successors(successors) do
    predecessors = Map.new(successors, fn {previous, next} -> {next, previous} end)

    successors
    |> Enum.flat_map(fn {previous, next} -> [previous, next] end)
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn id, chains -> elem(build(id, predecessors, chains, MapSet.new()), 1) end)
  end

  defp build(id, predecessors, chains, visited) do
    cond do
      Map.has_key?(chains, id) -> {chains[id], chains}
      MapSet.member?(visited, id) -> {nil, chains}
      true -> build_previous(id, predecessors, chains, MapSet.put(visited, id))
    end
  end

  defp build_previous(id, predecessors, chains, visited) do
    case Map.get(predecessors, id) do
      nil ->
        chain = %{first_spell: id, prev_spell: 0, rank: 1, req_spell: 0}
        {chain, Map.put(chains, id, chain)}

      previous ->
        case build(previous, predecessors, chains, visited) do
          {nil, chains} ->
            {nil, chains}

          {parent, chains} ->
            chain = %{parent | prev_spell: previous, rank: parent.rank + 1}
            {chain, Map.put(chains, id, chain)}
        end
    end
  end
end
