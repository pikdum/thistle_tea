defmodule ThistleTea.Game.Spell.StackRules do
  @moduledoc """
  Explicit aura conflicts and ordered upgrades compiled from spell groups.
  Group membership follows rank roots; upgrade lists retain exact spell IDs.
  """

  alias ThistleTea.Game.Spell

  defstruct groups: %{}, priorities: %{}, stronger: MapSet.new(), weaker: MapSet.new()

  def compile(members, rules, build) do
    groups =
      members
      |> Enum.filter(&(&1.build_min <= build and &1.build_max >= build))
      |> Enum.sort_by(&{&1.group_id, &1.group_spell_id, &1.spell_id})
      |> Enum.group_by(& &1.group_id, & &1.spell_id)

    rules =
      rules
      |> Enum.filter(&(&1.build <= build))
      |> Enum.group_by(& &1.group_id)
      |> Map.new(fn {id, versions} -> {id, Enum.max_by(versions, & &1.build).stack_rule} end)

    Enum.reduce(groups, %{}, fn {id, members}, spells ->
      rule = Map.get(rules, id, 0)
      expanded = expand(groups, id, MapSet.new())

      Enum.reduce(expanded, spells, fn spell_id, current ->
        data = Map.get(current, spell_id, %__MODULE__{})
        data = %{data | groups: Map.put(data.groups, id, rule)}
        Map.put(current, spell_id, put_priority(data, id, members, spell_id, rule))
      end)
    end)
  end

  def inherit(%__MODULE__{} = own, %__MODULE__{} = root) do
    %{own | groups: root.groups, priorities: Map.merge(root.priorities, own.priorities)}
  end

  def stronger_active?(%Spell{stack_rules: %__MODULE__{stronger: stronger}}, sources) do
    Enum.any?(sources, fn {id, _family, _flags_0, _flags_1, _caster} -> MapSet.member?(stronger, id) end)
  end

  def stronger_active?(_spell, _sources), do: false

  def validate(%Spell{} = spell, sources) do
    if positive?(spell) and not Spell.area_of_effect?(spell) and Spell.aura_effects(spell) != [] and
         stronger_active?(spell, sources),
       do: {:error, :aura_bounced},
       else: :ok
  end

  defp positive?(spell) do
    Spell.custom?(spell, :positive) or
      not (Spell.custom?(spell, :negative) or Spell.attribute?(spell, :negative) or Spell.harmful?(spell))
  end

  def relation(%Spell{} = existing, %Spell{} = incoming) do
    if linked?(existing, incoming), do: :none, else: compare(existing, incoming)
  end

  defp compare(%Spell{stack_rules: %__MODULE__{} = old} = existing, %Spell{stack_rules: %__MODULE__{} = new} = incoming) do
    rule = if active_conflict?(existing, incoming), do: group_relation(old, new)

    cond do
      rule in [:block, :replace] -> rule
      MapSet.member?(new.weaker, existing.id) -> :replace
      true -> :none
    end
  end

  defp compare(_existing, _incoming), do: :none

  defp active_conflict?(existing, incoming) do
    existing.id != incoming.id and not Spell.same_chain?(existing, incoming) and
      not Spell.attribute?(existing, :passive) and not Spell.attribute?(existing, :do_not_display)
  end

  defp group_relation(old, new) do
    common =
      old.groups
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.find(fn {id, rule} -> rule in [1, 3] and Map.has_key?(new.groups, id) end)

    case common do
      {id, 3} ->
        if Map.get(old.priorities, id, -1) > Map.get(new.priorities, id, -1), do: :block, else: :replace

      {_id, 1} ->
        :replace

      nil ->
        :none
    end
  end

  defp linked?(existing, incoming) do
    Enum.any?(existing.effects, &(&1.trigger_spell_id == incoming.id)) or
      Enum.any?(incoming.effects, &(&1.trigger_spell_id == existing.id))
  end

  defp put_priority(data, id, members, spell_id, 3) do
    case Enum.split_while(members, &(&1 != spell_id)) do
      {weaker, [^spell_id | stronger]} ->
        %{
          data
          | priorities: Map.put(data.priorities, id, length(weaker)),
            stronger: MapSet.union(data.stronger, MapSet.new(Enum.filter(stronger, &(&1 > 0)))),
            weaker: MapSet.union(data.weaker, MapSet.new(Enum.filter(weaker, &(&1 > 0))))
        }

      _missing ->
        data
    end
  end

  defp put_priority(data, _id, _members, _spell_id, _rule), do: data

  defp expand(groups, id, visited) do
    if MapSet.member?(visited, id) do
      MapSet.new()
    else
      visited = MapSet.put(visited, id)

      groups
      |> Map.get(id, [])
      |> Enum.reduce(MapSet.new(), fn
        child, found when child < 0 -> MapSet.union(found, expand(groups, -child, visited))
        spell, found when spell > 0 -> MapSet.put(found, spell)
        _invalid, found -> found
      end)
    end
  end
end
