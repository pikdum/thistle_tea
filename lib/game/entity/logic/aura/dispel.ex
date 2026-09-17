defmodule ThistleTea.Game.Entity.Logic.Aura.Dispel do
  @moduledoc """
  Selects dispellable holders and removes one stack per attempt, preserving
  remaining stacks and their schedules through the shared aura transition.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Aura.Transition
  alias ThistleTea.Game.Spell

  def apply(entity, dispel_type, now, polarity \\ nil, count \\ 1)

  def apply(%{unit: %Unit{auras: holders}} = entity, dispel_type, now, polarity, count)
      when is_list(holders) and is_integer(count) and count > 0 do
    candidates =
      holders
      |> Enum.with_index()
      |> Enum.filter(fn {%Holder{spell: spell, negative?: negative?}, _index} ->
        matches?(spell.dispel_type, if(negative?, do: :negative, else: :positive), dispel_type, polarity)
      end)

    {remaining, removed} = remove_stacks(candidates, count, %{})
    remaining = Map.new(remaining, fn {holder, index} -> {index, holder} end)

    kept =
      holders
      |> Enum.with_index()
      |> Enum.flat_map(fn {holder, index} ->
        if Map.has_key?(removed, index), do: List.wrap(Map.get(remaining, index)), else: [holder]
      end)

    {entity, events} = Transition.run(entity, %Change{holders: kept, cause: :dispelled, now: now})
    spell_ids = removed |> Enum.sort() |> Enum.map(fn {_index, id} -> id end)
    {entity, events, spell_ids}
  end

  def apply(entity, _dispel_type, _now, _polarity, _count), do: {entity, [], []}

  def matches?(aura_type, aura_polarity, dispel_type, polarity) do
    matches_type?(aura_type, dispel_type) and
      (aura_type not in [1, 4] or is_nil(polarity) or aura_polarity == polarity)
  end

  defp matches_type?(aura_type, dispel_type) when dispel_type == 7 or dispel_type < 0, do: aura_type in [1, 2, 3, 4]

  defp matches_type?(aura_type, dispel_type), do: aura_type == dispel_type

  defp remove_stacks(candidates, 0, removed), do: {candidates, removed}
  defp remove_stacks([], _count, removed), do: {[], removed}

  defp remove_stacks(candidates, count, removed) do
    {%Holder{spell: %Spell{id: id}, stacks: stacks} = holder, index} = Enum.random(candidates)

    candidates =
      if stacks > 1 do
        List.keyreplace(candidates, index, 1, {%{holder | stacks: stacks - 1}, index})
      else
        List.keydelete(candidates, index, 1)
      end

    remove_stacks(candidates, count - 1, Map.put(removed, index, id))
  end
end
