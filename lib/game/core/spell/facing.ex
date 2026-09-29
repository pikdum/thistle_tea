defmodule ThistleTea.Game.Core.Spell.Facing do
  @moduledoc "Pure spell-facing requirements, including positional abilities and vanilla close-range tolerance."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Spell

  @overlap_distance_squared 1.4 * 1.4

  def required?(caster, %Spell{} = spell, opts \\ []) do
    Spell.attribute?(spell, :from_behind) or Spell.attribute?(spell, :target_facing_caster) or
      requires_forward_target?(caster, spell, opts)
  end

  def validate(caster, %Spell{} = spell, target, opts \\ []) do
    cond do
      Spell.attribute?(spell, :from_behind) and not behind_target?(caster, target) ->
        {:error, :not_behind}

      Spell.attribute?(spell, :target_facing_caster) and behind_target?(caster, target) ->
        {:error, :not_infront}

      requires_forward_target?(caster, spell, opts) and not facing_target?(caster, target) ->
        {:error, :unit_not_infront}

      true ->
        :ok
    end
  end

  defp requires_forward_target?(caster, spell, opts) do
    not Keyword.get(opts, :triggered?, false) and not Spell.attribute?(spell, :on_next_swing) and
      (spell.melee_range? or player_forward_spell?(caster, spell))
  end

  defp player_forward_spell?(%Character{}, %Spell{} = spell),
    do: Spell.custom?(spell, :face_target) or Spell.auto_repeat?(spell)

  defp player_forward_spell?(_caster, _spell), do: false

  defp facing_target?(%{movement_block: %{position: {x, y, _z, orientation}}}, %{position: {_world, tx, ty, _tz}})
       when is_number(orientation) do
    dx = tx - x
    dy = ty - y
    dx * dx + dy * dy < @overlap_distance_squared or forward?(orientation, :math.atan2(dy, dx))
  end

  defp facing_target?(_caster, _target), do: true

  defp behind_target?(%{movement_block: %{position: {x, y, _z, _orientation}}}, %{
         position: {_world, tx, ty, _tz},
         orientation: orientation
       })
       when is_number(orientation) do
    not forward?(orientation, :math.atan2(y - ty, x - tx))
  end

  defp behind_target?(_caster, _target), do: false

  defp forward?(orientation, angle) do
    difference = :math.fmod(angle - orientation, 2 * :math.pi())
    difference = if difference > :math.pi(), do: difference - 2 * :math.pi(), else: difference
    difference = if difference < -:math.pi(), do: difference + 2 * :math.pi(), else: difference
    abs(difference) <= :math.pi() / 2
  end
end
