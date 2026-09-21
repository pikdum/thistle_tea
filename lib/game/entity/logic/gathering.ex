defmodule ThistleTea.Game.Entity.Logic.Gathering do
  @moduledoc """
  Gathering difficulty, skill gains, and mineral-vein exhaustion at default
  vanilla rates. Rolls are supplied by the owning boundary.
  """
  import Bitwise, only: [<<<: 2]

  def attempt?(skill_id, value, required, roll) do
    (skill_id in [182, 186] and value >= 300) or required <= roll
  end

  def skill_up(skills, skill_id, required, roll, multiplier \\ 1) do
    with %{value: value, max: cap} = entry when value < cap <- Map.get(skills || %{}, skill_id),
         true <- roll < gain_chance(skill_id, value, required, multiplier) do
      {:gained, Map.put(skills, skill_id, %{entry | value: value + 1})}
    else
      _ -> :unchanged
    end
  end

  def gain_chance(skill_id, value, required, multiplier \\ 1)

  def gain_chance(skill_id, value, required, multiplier) when skill_id in [182, 186, 393, 633] do
    chance =
      cond do
        value >= required + 100 -> 0
        value >= required + 50 -> 25
        value >= required + 25 -> 75
        true -> 100
      end

    divisor = if skill_id in [186, 393], do: 1 <<< div(value, 75), else: 1
    min(chance * multiplier / divisor, 100)
  end

  def gain_chance(_skill_id, _value, _required, _multiplier), do: 0

  def replenish?(uses, minimum, maximum, skill, required, roll) do
    cond do
      minimum <= 0 or maximum <= minimum -> false
      uses >= maximum -> false
      uses < minimum -> true
      true -> roll < 100 * :math.pow(0.8, 4 * uses / maximum) + skill / (required + 25)
    end
  end
end
