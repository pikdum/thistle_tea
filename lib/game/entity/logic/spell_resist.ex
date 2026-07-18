defmodule ThistleTea.Game.Entity.Logic.SpellResist do
  @moduledoc """
  Vanilla spell hit and resistance rolls ported from vmangos: the level-based
  binary spell miss (`MagicSpellHitChance`, 96% at even level with a floor of
  22% hit) rolled by the caster, and partial school-damage resistance
  (`GetSpellResistChance` + the 0/25/50/75% bucket table from
  `RollMagicResistanceMultiplierOutcomeAgainst`) rolled by the target, with
  DoT ticks a tenth as likely to resist.
  """
  alias ThistleTea.Game.Math

  @hit_floor_percent 22
  @resist_cap 0.75

  @resist_values [
    {0, 0, 0, 0, 0},
    {3, 0, 0, 2, 6},
    {5, 0, 1, 4, 12},
    {8, 0, 1, 5, 18},
    {10, 0, 1, 7, 23},
    {13, 0, 2, 9, 28},
    {15, 0, 2, 11, 33},
    {18, 0, 2, 13, 37},
    {20, 0, 3, 15, 41},
    {23, 1, 3, 17, 46},
    {25, 1, 4, 19, 47},
    {28, 1, 5, 21, 48},
    {30, 1, 6, 24, 49},
    {33, 1, 8, 28, 47},
    {35, 1, 9, 33, 43},
    {38, 1, 11, 37, 39},
    {40, 1, 13, 41, 35},
    {43, 1, 16, 45, 30},
    {45, 1, 18, 48, 26},
    {48, 2, 20, 48, 24},
    {50, 4, 23, 48, 21},
    {53, 5, 25, 47, 19},
    {55, 7, 28, 45, 17},
    {58, 9, 31, 43, 16},
    {60, 11, 34, 40, 14},
    {62, 13, 37, 37, 12},
    {65, 15, 41, 33, 10},
    {68, 18, 44, 29, 8},
    {70, 20, 48, 25, 7},
    {73, 23, 51, 20, 5},
    {75, 25, 55, 16, 3}
  ]

  def magic_hit_chance_bp(caster_level, target_level, target_player?) do
    level_diff = target_level - caster_level
    per_level = if target_player?, do: 7, else: 11

    hit =
      if level_diff < 3 do
        96 - level_diff
      else
        94 - (level_diff - 2) * per_level
      end

    hit
    |> max(@hit_floor_percent)
    |> Kernel.*(100)
    |> max(100)
    |> min(9_900)
  end

  def magic_hit?(caster_level, target_level, target_player?, opts \\ []) do
    roll = Keyword.get_lazy(opts, :roll, fn -> Math.random_int(0, 9_999) end)
    hit_bonus_bp = trunc(Keyword.get(opts, :hit_bonus, 0) * 100)

    chance_bp =
      (magic_hit_chance_bp(caster_level, target_level, target_player?) + hit_bonus_bp)
      |> max(100)
      |> min(9_900)

    roll < chance_bp
  end

  def resist_chance(resistance, caster_level, target_creature?, level_diff) do
    caster_level = max(caster_level || 1, 1)
    resistance = max(resistance || 0, 0)

    resistance =
      if target_creature? do
        resistance + trunc(8.0 * level_diff * caster_level / 63.0)
      else
        resistance
      end

    (resistance * 0.15 / caster_level)
    |> max(0.0)
    |> min(@resist_cap)
  end

  def resist_fraction(resistance, caster_level, opts \\ []) do
    chance =
      resist_chance(
        resistance,
        caster_level,
        Keyword.get(opts, :target_creature?, true),
        Keyword.get(opts, :level_diff, 0)
      ) * 100.0

    chance = if Keyword.get(opts, :dot?, false), do: chance * 0.1, else: chance

    roll = Keyword.get_lazy(opts, :roll, fn -> Math.random_int(0, 99) end)
    roll_bucket(chance, roll)
  end

  def resisted_amount(damage, resistance, caster_level, opts \\ []) when is_integer(damage) do
    if damage > 0 do
      trunc(damage * resist_fraction(resistance, caster_level, opts))
    else
      0
    end
  end

  defp roll_bucket(chance, roll) do
    {resist100, resist75, resist50, resist25} = interpolate(chance)

    cond do
      roll < resist100 + resist75 -> 0.75
      roll < resist100 + resist75 + resist50 -> 0.5
      roll < resist100 + resist75 + resist50 + resist25 -> 0.25
      true -> 0.0
    end
  end

  defp interpolate(chance) do
    chance = chance |> max(0.0) |> min(75.0)
    index = @resist_values |> Enum.find_index(fn {threshold, _, _, _, _} -> threshold >= chance end) |> max(1)

    {prev_threshold, p100, p75, p50, p25} = Enum.at(@resist_values, index - 1)
    {next_threshold, n100, n75, n50, n25} = Enum.at(@resist_values, index)

    coeff = (chance - prev_threshold) / max(next_threshold - prev_threshold, 1)

    {
      p100 + (n100 - p100) * coeff,
      p75 + (n75 - p75) * coeff,
      p50 + (n50 - p50) * coeff,
      p25 + (n25 - p25) * coeff
    }
  end
end
