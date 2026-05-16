defmodule ThistleTea.Game.Spell.Effect do
  defstruct [
    :index,
    :type,
    :base_points,
    :die_sides,
    :real_points_per_level,
    :aura,
    :amplitude_ms,
    :misc_value,
    :radius_yards,
    :implicit_target_a,
    :implicit_target_b,
    :chain_targets,
    :trigger_spell_id
  ]

  def damage_roll(%__MODULE__{base_points: base, die_sides: sides})
      when is_integer(base) and is_integer(sides) and sides > 0 do
    base + Enum.random(1..sides)
  end

  def damage_roll(%__MODULE__{base_points: base}) when is_integer(base), do: base
  def damage_roll(%__MODULE__{}), do: 0
end
