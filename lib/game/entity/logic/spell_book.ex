defmodule ThistleTea.Game.Entity.Logic.SpellBook do
  @moduledoc """
  Computes the changes to a known-spell set when learning new spells, removing
  ranks that the new spells supersede.
  """
  def learn(known_ids, new_ids, superseded_by) do
    known_ids = known_ids || []

    new_ids =
      new_ids
      |> Enum.uniq()
      |> order_by_supersession(superseded_by)

    Enum.reduce(new_ids, {known_ids, []}, &learn_one(&1, &2, superseded_by))
  end

  defp learn_one(spell_id, {ids, events}, superseded_by) do
    case Enum.find(ids, fn known -> Map.get(superseded_by, known) == spell_id end) do
      nil -> learn_new(ids, events, spell_id)
      old -> supersede(ids, events, old, spell_id)
    end
  end

  defp order_by_supersession(spell_ids, superseded_by) do
    predecessor_by_id = Map.new(superseded_by, fn {old_id, new_id} -> {new_id, old_id} end)
    Enum.sort_by(spell_ids, &supersession_depth(&1, predecessor_by_id, MapSet.new()))
  end

  defp supersession_depth(spell_id, predecessor_by_id, visited) do
    case Map.get(predecessor_by_id, spell_id) do
      nil ->
        0

      predecessor ->
        if MapSet.member?(visited, predecessor) do
          0
        else
          1 + supersession_depth(predecessor, predecessor_by_id, MapSet.put(visited, predecessor))
        end
    end
  end

  defp learn_new(ids, events, spell_id) do
    if spell_id in ids do
      {ids, events}
    else
      {ids ++ [spell_id], events ++ [{:learned, spell_id}]}
    end
  end

  defp supersede(ids, events, old_id, spell_id) do
    already_known? = spell_id in ids
    ids = ids |> List.delete(old_id) |> append_new(spell_id)
    event = if already_known?, do: {:removed, old_id}, else: {:superseded, old_id, spell_id}
    {ids, events ++ [event]}
  end

  defp append_new(ids, spell_id) do
    if spell_id in ids, do: ids, else: ids ++ [spell_id]
  end
end
