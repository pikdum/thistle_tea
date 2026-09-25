defmodule ThistleTea.Game.Spell.Destination do
  @moduledoc "Validates explicit ground destinations before a cast is admitted."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Target

  def validate(caster, %Spell{} = spell, %Target{selection: :none, destination_location: destination}, los?)
      when is_tuple(destination) do
    with :ok <- check_range(caster, spell, destination) do
      if los? == false and not Spell.attribute?(spell, :ignore_line_of_sight),
        do: {:error, :line_of_sight},
        else: :ok
    end
  end

  def validate(_caster, _spell, _targets, _los?), do: :ok

  defp check_range(
         %{unit: unit, movement_block: %{position: {x, y, z, _}}} = caster,
         %Spell{range_yards: range, min_range_yards: minimum} = spell,
         destination
       )
       when is_number(range) and range > 0 do
    radius = if is_number(unit.bounding_radius), do: max(unit.bounding_radius, 0), else: 0
    distance = max(Math.distance({x, y, z}, destination) - radius, 0)
    maximum = Modifiers.value(caster, spell, :range, range) + leeway(caster)

    cond do
      distance > maximum -> {:error, :out_of_range}
      is_number(minimum) and minimum > 0 and distance < minimum -> {:error, :too_close}
      true -> :ok
    end
  end

  defp check_range(_caster, _spell, _destination), do: :ok

  defp leeway(%Character{}), do: 1.25
  defp leeway(_caster), do: 0.0
end
