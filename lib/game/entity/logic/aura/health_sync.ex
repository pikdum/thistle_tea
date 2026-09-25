defmodule ThistleTea.Game.Entity.Logic.Aura.HealthSync do
  @moduledoc "Preserves proportional form health and handles temporary health grants across aura transitions."

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell

  @temporary_health_spells [12_976, 23_782]

  defguardp positive_integer(value) when is_integer(value) and value > 0

  def sync(
        %{unit: %Unit{max_health: maximum} = unit} = entity,
        %Unit{health: health, max_health: previous_max} = previous
      )
      when positive_integer(health) and positive_integer(previous_max) and positive_integer(maximum) do
    old_stamina = stamina_holders(previous.auras || [], true)
    new_stamina = stamina_holders(unit.auras || [], true)
    stamina_changed? = stamina_multiplier(old_stamina) != stamina_multiplier(new_stamina)
    bear_changed? = bear_health(previous) != bear_health(unit)
    temporary_delta = temporary_health(unit) - temporary_health(previous)

    if stamina_changed? or bear_changed? or temporary_delta != 0 do
      intermediate_max = intermediate_maximum(unit, old_stamina, stamina_changed?)
      health = health + temporary_delta

      health = scale_bear_health(health, previous_max, intermediate_max, bear_changed?)
      health = if stamina_changed?, do: div(maximum * health, intermediate_max), else: health
      %{entity | unit: %{unit | health: health |> max(1) |> min(maximum)}}
    else
      entity
    end
  end

  def sync(entity, _previous), do: entity

  defp scale_bear_health(health, previous_max, maximum, true),
    do: div(maximum * health + previous_max - 1, previous_max)

  defp scale_bear_health(health, _previous_max, maximum, false), do: min(health, maximum)

  defp intermediate_maximum(unit, old_stamina, true) do
    intermediate = %{unit | auras: stamina_holders(unit.auras || [], false) ++ old_stamina} |> Stats.recompute()
    intermediate.max_health
  end

  defp intermediate_maximum(unit, _old_stamina, false), do: unit.max_health

  defp stamina_holders(holders, keep?) do
    for holder <- holders,
        auras = Enum.filter(holder.auras, &(proportional_stamina?(holder.spell, &1) == keep?)),
        auras != [],
        do: %{holder | auras: auras}
  end

  defp proportional_stamina?(spell, %Aura{type: :mod_total_stat_percent, misc_value: 2}),
    do: Spell.attribute?(spell, :ability)

  defp proportional_stamina?(_spell, _aura), do: false

  defp stamina_multiplier(holders) do
    holders
    |> Enum.flat_map(fn holder -> Enum.map(holder.auras, &(&1.amount * holder.stacks)) end)
    |> Enum.sort()
    |> Enum.reduce(1.0, fn amount, multiplier -> multiplier * max(100 + amount, 0) / 100 end)
  end

  defp bear_health(%Unit{auras: holders}) do
    holders
    |> List.wrap()
    |> Enum.filter(&Enum.any?(&1.auras, fn aura -> aura.type == :mod_shapeshift and aura.misc_value in [5, 8] end))
    |> flat_health()
  end

  defp temporary_health(%Unit{auras: holders}) do
    holders |> List.wrap() |> Enum.filter(&(&1.spell.id in @temporary_health_spells)) |> flat_health()
  end

  defp flat_health(holders) do
    for %Holder{auras: auras} <- holders,
        %Aura{type: :mod_increase_health, amount: amount} <- auras,
        reduce: 0 do
      total -> total + amount
    end
  end
end
