defmodule ThistleTea.Game.Entity.Logic.SpellResist do
  @moduledoc """
  Vanilla spell hit and resistance rolls ported from vmangos: the level-based
  spell miss (`MagicSpellHitChance`, 96% at even level with a floor of
  22% hit) rolled by the caster, and partial school-damage resistance
  (`GetSpellResistChance` + the 0/25/50/75% bucket table from
  `RollMagicResistanceMultiplierOutcomeAgainst`) rolled by the target, with
  DoT ticks a tenth as likely to resist.
  """
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.MechanicResistance
  alias ThistleTea.Game.Entity.Logic.ResistancePenetration
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Modifiers

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

  def hit_snapshot(caster) do
    modifiers =
      Enum.filter(Modifiers.snapshot_all(caster), fn {_family, aura} ->
        Modifiers.operation(aura.misc_value) == :resist_miss_chance
      end)

    %{base: Aura.flat_amount(caster, :mod_spell_hit_chance), modifiers: modifiers}
  end

  def hit_bonus(%{base: base, modifiers: modifiers}, spell) do
    base + Modifiers.value(Modifiers.for_spell(modifiers, spell), :resist_miss_chance, 0)
  end

  def school_resistances(%{unit: %Unit{} = unit}) do
    %{
      1 => unit.holy_resistance || 0,
      2 => unit.fire_resistance || 0,
      3 => unit.nature_resistance || 0,
      4 => unit.frost_resistance || 0,
      5 => unit.shadow_resistance || 0,
      6 => unit.arcane_resistance || 0
    }
  end

  def spell_hit?(caster, %Spell{} = spell, target, target_player?, opts \\ []) do
    caster_level = max(caster.unit.level || 1, 1)

    hit_bonus = hit_bonus(hit_snapshot(caster), spell)

    context = %CastContext{
      caster_level: caster_level,
      spell_hit_bonus: hit_bonus,
      resistance_penetration: ResistancePenetration.snapshot(caster)
    }

    context_hit?(context, spell, target, target_player?, opts)
  end

  def context_hit?(%CastContext{} = context, %Spell{} = spell, target, target_player?, opts \\ []) do
    Map.get(target, :alive?) == false or Map.get(target, :no_spell_defense?, false) or
      Spell.attribute?(spell, :always_hit) or
      Keyword.get_lazy(opts, :roll, fn -> Math.random_int(0, 9_999) end) <
        context_hit_chance_bp(context, spell, target, target_player?)
  end

  def context_hit_chance_bp(%CastContext{} = context, %Spell{} = spell, target, target_player?) do
    if Spell.attribute?(spell, :always_hit),
      do: 10_000,
      else: context_hit_chance(context, spell, target, target_player?)
  end

  defp context_hit_chance(context, spell, target, target_player?) do
    caster_level = max(context.caster_level || 1, 1)
    target_level = max(Map.get(target, :level) || caster_level, 1)
    target_bonus = Aura.versus_amount(Map.get(target, :attacker_spell_hit_chance), Spell.school_mask(spell))

    magic_hit_chance_bp(
      caster_level,
      target_level,
      target_player?,
      hit_bonus: context.spell_hit_bonus + target_bonus,
      mechanic_resistance: MechanicResistance.chance(Map.get(target, :mechanic_resistance), spell.mechanic),
      binary_resistance: binary_resistance(context, spell, target)
    )
  end

  defp binary_resistance(context, spell, target) do
    if Spell.binary?(spell) do
      base = Map.get(Map.get(target, :school_resistances) || %{}, Spell.school_index(spell), 0)
      ResistancePenetration.resistance(base, context.resistance_penetration, spell)
    else
      0
    end
  end

  def magic_hit_chance_bp(caster_level, target_level, target_player?, opts \\ []) do
    hit_bonus_bp = Keyword.get(opts, :hit_bonus, 0) * 100
    mechanic_resistance_bp = Keyword.get(opts, :mechanic_resistance, 0) * 100
    binary_resistance = Keyword.get(opts, :binary_resistance, 0)
    school_multiplier = 1 - resist_chance(binary_resistance, caster_level, false, 0)

    ((level_hit_chance(caster_level, target_level, target_player?) * 100 + hit_bonus_bp - mechanic_resistance_bp) *
       school_multiplier)
    |> trunc()
    |> max(100)
    |> min(9_900)
  end

  defp level_hit_chance(caster_level, target_level, target_player?) do
    level_diff = target_level - caster_level
    per_level = if target_player?, do: 7, else: 11

    hit =
      if level_diff < 3 do
        96 - level_diff
      else
        94 - (level_diff - 2) * per_level
      end

    max(hit, @hit_floor_percent)
  end

  def magic_hit?(caster_level, target_level, target_player?, opts \\ []) do
    Keyword.get(opts, :no_spell_defense?, false) or roll_magic_hit?(caster_level, target_level, target_player?, opts)
  end

  defp roll_magic_hit?(caster_level, target_level, target_player?, opts) do
    roll = Keyword.get_lazy(opts, :roll, fn -> Math.random_int(0, 9_999) end)
    roll < magic_hit_chance_bp(caster_level, target_level, target_player?, opts)
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
    if damage > 0 and not Spell.binary?(Keyword.get(opts, :spell)) do
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
