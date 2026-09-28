defmodule ThistleTea.Game.Spell.CostScaling do
  @moduledoc "Vanilla power-cost scaling from creature level or the player's associated spell skill."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Spell

  def base_cost(caster, %Spell{} = spell) do
    rank = caster |> rank(spell) |> cap_rank(spell.max_level)
    (spell.mana_cost || 0) + (spell.mana_cost_per_level || 0) * (div(rank, 5) - (spell.base_level || 0))
  end

  def apply_level_multiplier(%{unit: %{level: level}}, %Spell{spell_level: spell_level} = spell, cost)
      when is_integer(level) and level > 0 and is_integer(spell_level) and spell_level > 0 do
    divisor = 1.117 * spell_level / level - 0.1327

    cond do
      not Spell.attribute?(spell, :scales_with_creature_level) -> cost
      divisor == 0 -> 0
      true -> trunc(cost / divisor)
    end
  end

  def apply_level_multiplier(_caster, _spell, cost), do: cost

  defp rank(%Character{player: %{skills: skills}} = caster, %Spell{cost_skill_id: id}) when is_integer(id) do
    {temporary, permanent} = Map.get(Skills.bonuses(caster), id, {0, 0})
    if Skills.known?(skills, id), do: max(Skills.value(skills, id) + temporary + permanent, 0), else: 0
  end

  defp rank(%Character{}, _spell), do: 0
  defp rank(%{unit: %{level: level}}, _spell) when is_integer(level), do: max(level, 0)
  defp rank(_caster, _spell), do: 0

  defp cap_rank(rank, maximum) when is_integer(maximum) and maximum > 0, do: min(rank, maximum * 5)
  defp cap_rank(rank, _maximum), do: rank
end
