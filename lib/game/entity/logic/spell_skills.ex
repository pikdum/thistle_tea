defmodule ThistleTea.Game.Entity.Logic.SpellSkills do
  @moduledoc "Skill ranks granted by known spells, including profession caps and trained riding values."

  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  def grants(%Spell{effects: effects}) do
    case Enum.find(effects, &(&1.type == :skill)) do
      %Effect{misc_value: id, base_points: points, base_dice: dice}
      when is_integer(id) and id > 0 and is_integer(points) and is_integer(dice) and points + dice > 0 ->
        cap = (points + dice) * 75
        skills = Skills.learn_rank(%{}, id, cap)
        if id == 762, do: put_in(skills[id].value, cap), else: skills

      _missing ->
        %{}
    end
  end

  def grants(spellbook) when is_map(spellbook) do
    spellbook |> Map.values() |> Enum.reduce(%{}, &learn(&2, grants(&1)))
  end

  def learn(skills, grants) do
    Enum.reduce(grants, skills, fn {id, grant}, skills ->
      skills = Skills.learn_rank(skills, id, grant.max)
      put_in(skills[id].value, max(skills[id].value, grant.value))
    end)
  end

  def remove(skills, previous, current) do
    Enum.reduce(previous, skills, fn {id, old}, skills ->
      case {Map.get(skills, id), Map.get(current, id)} do
        {_, nil} ->
          Map.delete(skills, id)

        {%{} = entry, %{max: cap} = grant} when cap < old.max ->
          Map.put(skills, id, %{entry | value: min(entry.value, grant.value), max: cap, step: grant.step})

        _unchanged ->
          skills
      end
    end)
  end
end
