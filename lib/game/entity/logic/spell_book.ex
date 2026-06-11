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
      |> Enum.reject(&(&1 in known_ids))

    Enum.reduce(new_ids, {known_ids, []}, fn spell_id, {ids, events} ->
      # credo:disable-for-next-line Credo.Check.Refactor.Nesting
      case Enum.find(ids, fn known -> Map.get(superseded_by, known) == spell_id end) do
        nil -> {ids ++ [spell_id], events ++ [{:learned, spell_id}]}
        old -> {List.delete(ids, old) ++ [spell_id], events ++ [{:superseded, old, spell_id}]}
      end
    end)
  end
end
