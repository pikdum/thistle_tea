defmodule ThistleTea.Game.Spell.Radius do
  @moduledoc "Computes area radii from spell data and the caster's matching spell modifiers."

  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers

  def maximum(effects, modifiers, fallback \\ 0.0) do
    effects
    |> Enum.map(& &1.radius_yards)
    |> Enum.filter(&is_number/1)
    |> Enum.max(fn -> fallback end)
    |> modified(modifiers)
  end

  def effect(%Effect{radius_yards: radius}, modifiers, fallback \\ 0.0) do
    radius = if is_number(radius) and radius > 0, do: radius, else: fallback
    modified(radius, modifiers)
  end

  defp modified(radius, modifiers) when is_number(radius), do: max(Modifiers.value(modifiers, :radius, radius), 0.0)
  defp modified(radius, _modifiers), do: radius
end
