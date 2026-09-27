defmodule ThistleTea.Game.Spell.Range do
  @moduledoc "Computes maximum cast and channel ranges from base spell data and matching caster modifiers."

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Modifiers

  def maximum(caster, %Spell{range_yards: range} = spell) when is_number(range) and range > 0 do
    modified(caster, spell, range)
  end

  def maximum(_caster, %Spell{range_yards: range}), do: range

  def channel_maximum(caster, %Spell{range_yards: range} = spell, hostile?) when is_number(range) and range > 0 do
    range = if hostile?, do: range * 1.33, else: range + 1.25
    modified(caster, spell, range)
  end

  def channel_maximum(_caster, %Spell{range_yards: range}, _hostile?), do: range

  defp modified(caster, spell, range), do: max(Modifiers.value(caster, spell, :range, range), 0.0)
end
