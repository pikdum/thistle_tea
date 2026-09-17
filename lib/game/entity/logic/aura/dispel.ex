defmodule ThistleTea.Game.Entity.Logic.Aura.Dispel do
  @moduledoc """
  Attempts one dispel per selected stack. Resisted attempts leave their stacks
  intact; successful removals share the aura transition and preserve schedules.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Aura.Transition

  def apply(entity, dispel_type, now, polarity \\ nil, count \\ 1) do
    {entity, events, removed, _failed} = attempt(entity, dispel_type, now, polarity, count)
    {entity, events, removed}
  end

  def attempt(entity, dispel_type, now, polarity, count, opts \\ [])

  def attempt(%{unit: %Unit{auras: holders}} = entity, dispel_type, now, polarity, count, opts)
      when is_list(holders) and is_integer(count) and count > 0 do
    candidates =
      holders
      |> Enum.with_index()
      |> Enum.filter(fn {%Holder{spell: spell, negative?: negative?}, _index} ->
        matches?(spell.dispel_type, if(negative?, do: :negative, else: :positive), dispel_type, polarity)
      end)

    {removed, failed} = attempt_stacks(candidates, count, %{}, [], opts)
    kept = remaining_holders(holders, removed)
    {entity, events} = Transition.run(entity, %Change{holders: kept, cause: :dispelled, now: now})
    spell_ids = removed |> Enum.sort() |> Enum.map(fn {index, _count} -> Enum.at(holders, index).spell.id end)
    {entity, events, spell_ids, Enum.reverse(failed)}
  end

  def attempt(entity, _dispel_type, _now, _polarity, _count, _opts), do: {entity, [], [], []}

  def matches?(aura_type, aura_polarity, dispel_type, polarity) do
    matches_type?(aura_type, dispel_type) and
      (aura_type not in [1, 4] or is_nil(polarity) or aura_polarity == polarity)
  end

  defp matches_type?(aura_type, dispel_type) when dispel_type == 7 or dispel_type < 0, do: aura_type in [1, 2, 3, 4]

  defp matches_type?(aura_type, dispel_type), do: aura_type == dispel_type

  defp attempt_stacks(candidates, count, removed, failed, _opts) when count == 0 or candidates == [],
    do: {removed, failed}

  defp attempt_stacks(candidates, count, removed, failed, opts) do
    choose = Keyword.get(opts, :choose, &Enum.random/1)
    {holder, index} = choose.(candidates)
    candidates = spend_attempt(candidates, holder, index)

    if resisted?(holder, opts) do
      attempt_stacks(candidates, count - 1, removed, [holder.spell.id | failed], opts)
    else
      removed = Map.update(removed, index, 1, &(&1 + 1))
      attempt_stacks(candidates, count - 1, removed, failed, opts)
    end
  end

  defp spend_attempt(candidates, %Holder{stacks: stacks} = holder, index) do
    if stacks > 1 do
      List.keyreplace(candidates, index, 1, {%{holder | stacks: stacks - 1}, index})
    else
      List.keydelete(candidates, index, 1)
    end
  end

  defp resisted?(%Holder{spell: spell, caster_guid: caster}, opts) do
    chance = opts |> Keyword.get(:resistance, %{}) |> Map.get({spell.id, caster}, 0)
    roll = Keyword.get(opts, :roll, fn -> :rand.uniform(100) end)
    chance > 0 and (chance >= 100 or roll.() <= chance)
  end

  defp remaining_holders(holders, removed) do
    holders
    |> Enum.with_index()
    |> Enum.flat_map(fn {holder, index} ->
      stacks = holder.stacks - Map.get(removed, index, 0)
      if stacks > 0, do: [%{holder | stacks: stacks}], else: []
    end)
  end
end
