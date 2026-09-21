defmodule ThistleTea.Game.Entity.Logic.Crafting do
  @moduledoc "Pure recipe skill gains shared by crafting and enchanting."

  alias ThistleTea.Game.Entity.Data.Character

  def skill_up(%Character{} = character, %{skill_id: id, yellow: yellow, gray: gray}, roll) do
    case Map.get(character.player.skills, id) do
      %{value: value, max: cap} = skill when value < cap ->
        if roll < gain_chance(value, yellow, gray) do
          skills = Map.put(character.player.skills, id, %{skill | value: value + 1})
          %{character | player: %{character.player | skills: skills}}
        else
          character
        end

      _ ->
        character
    end
  end

  def skill_up(character, _recipe, _roll), do: character

  defp gain_chance(value, _yellow, gray) when value >= gray, do: 0
  defp gain_chance(value, yellow, gray) when value >= div(yellow + gray, 2), do: 25
  defp gain_chance(value, yellow, _gray) when value >= yellow, do: 75
  defp gain_chance(_value, _yellow, _gray), do: 100
end
