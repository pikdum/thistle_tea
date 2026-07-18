defmodule ThistleTea.Game.Spell.Coefficient do
  @moduledoc """
  Spell-power/healing bonus coefficients, ported from VMangos: per-effect
  `spell_template` coefficients win outright; otherwise the cast-time
  formula with DoT splitting, AoE halving, leech halving, extra-effect
  penalties, and the sub-level-20 penalty.
  """
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  @direct_damage_effects [:school_damage, :power_drain, :health_leech, :power_burn, :heal]
  @over_time_auras [:periodic_damage, :periodic_heal, :periodic_leech]

  def bonus(benefit, %Spell{} = spell, %Effect{} = effect, damage_type)
      when is_integer(benefit) and benefit > 0 and damage_type in [:direct, :dot] do
    trunc(benefit * value(spell, effect, damage_type))
  end

  def bonus(_benefit, _spell, _effect, _damage_type), do: 0

  def value(%Spell{}, %Effect{bonus_coefficient: coefficient}, _damage_type)
      when is_number(coefficient) and coefficient >= 0 do
    coefficient
  end

  def value(%Spell{} = spell, %Effect{}, damage_type) do
    default_coefficient(spell, damage_type) * level_penalty(spell)
  end

  defp default_coefficient(%Spell{} = spell, damage_type) do
    dot_factor =
      if damage_type == :dot do
        base = if channeled?(spell), do: 1.0, else: max(spell.duration_ms || 0, 0) / 15_000

        case max_ticks(spell) do
          ticks when ticks > 0 -> base / ticks
          _ -> base
        end
      else
        1.0
      end

    cast_time_for_bonus(spell, damage_type) / 3500 * dot_factor
  end

  defp level_penalty(%Spell{spell_level: spell_level}) when is_integer(spell_level) and spell_level in 1..20 do
    1.0 - (20 - spell_level) * 0.0375
  end

  defp level_penalty(_spell), do: 1.0

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp cast_time_for_bonus(%Spell{effects: effects} = spell, damage_type) do
    base_time = if channeled?(spell), do: spell.duration_ms || 0, else: spell.cast_time_ms || 0
    casting_time = clamp_cast_time(base_time)
    casting_time = if damage_type == :dot and not channeled?(spell), do: 3500, else: casting_time

    over_time = if Enum.any?(effects, &(&1.aura in @over_time_auras)), do: max(spell.duration_ms || 0, 0), else: 0
    direct? = Enum.any?(effects, &(&1.type in @direct_damage_effects))

    casting_time =
      if over_time > 0 and casting_time > 0 and direct? do
        original = clamp_cast_time(spell.cast_time_ms || 0)
        over_time_portion = over_time / 15_000 / (over_time / 15_000 + original / 3500)

        cond do
          damage_type == :dot -> casting_time * over_time_portion
          over_time_portion < 1.0 -> casting_time * (1.0 - over_time_portion)
          true -> 0.0
        end
      else
        casting_time
      end

    casting_time = if Enum.any?(effects, & &1.area_target?), do: casting_time / 2, else: casting_time

    casting_time = if leech?(effects), do: casting_time / 2, else: casting_time

    casting_time * :math.pow(0.95, extra_effects(effects))
  end

  defp clamp_cast_time(cast_time_ms), do: cast_time_ms |> max(1500) |> min(7000)

  defp leech?(effects) do
    Enum.any?(effects, &(&1.type == :health_leech or &1.aura == :periodic_leech))
  end

  defp extra_effects(effects) do
    Enum.reduce(effects, 0, fn %Effect{aura: aura}, count ->
      case aura do
        :dummy -> count + 1
        :mod_decrease_speed -> count + 1
        aura when aura in [:mod_confuse, :mod_stun, :mod_root] -> count + 2
        _ -> count
      end
    end)
  end

  defp max_ticks(%Spell{effects: effects} = spell) do
    duration = max(spell.duration_ms || 0, 0)

    effects
    |> Enum.filter(&(&1.aura in @over_time_auras and is_integer(&1.amplitude_ms) and &1.amplitude_ms > 0))
    |> Enum.map(&div(duration, &1.amplitude_ms))
    |> Enum.max(fn -> 0 end)
  end

  defp channeled?(%Spell{} = spell), do: Spell.attribute?(spell, :channeled)
end
