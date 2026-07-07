defmodule ThistleTea.Game.Entity.Logic.Resources do
  @moduledoc """
  Spending and gaining unit power: spell power costs (marking the five-second
  rule), health-cost spells, and rage generation from combat using the vanilla
  conversion formula. Rage is stored pre-scaled ×10, matching the client's
  units.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Spell

  @mana_power_type 0
  @rage_power_type 1
  @health_power_type -2
  @berserker_rage_spell_id 18_499

  @rage_dealt_factor 7.5
  @rage_taken_factor 2.5
  @berserker_rage_taken_multiplier 1.3

  @power_fields %{0 => :power1, 1 => :power2, 2 => :power3, 3 => :power4, 4 => :power5}
  @max_power_fields %{0 => :max_power1, 1 => :max_power2, 2 => :max_power3, 3 => :max_power4, 4 => :max_power5}

  def spend_power(%{internal: %Internal{godmode: true}} = entity, %Spell{power_type: power_type}, _now)
      when power_type in [@mana_power_type, @health_power_type], do: entity

  def spend_power(entity, %Spell{power_type: power_type} = spell, now) when is_integer(now) do
    do_spend(entity, power_type, power_cost(entity, spell), now)
  end

  def spend_power(entity, _spell, _now), do: entity

  def power_cost(entity, %Spell{mana_cost: cost, mana_cost_percent: percent, power_type: power_type}) do
    (cost || 0) + percent_cost(entity, power_type, percent)
  end

  def power_cost(_entity, _spell), do: 0

  defp percent_cost(entity, power_type, percent) when is_integer(percent) and percent > 0 do
    div(percent_cost_base(entity, power_type) * percent, 100)
  end

  defp percent_cost(_entity, _power_type, _percent), do: 0

  defp percent_cost_base(%{unit: %Unit{base_health: base_health}}, @health_power_type)
       when is_integer(base_health) and base_health > 0, do: base_health

  defp percent_cost_base(%{unit: %Unit{max_health: max_health}}, @health_power_type) when is_integer(max_health),
    do: max_health

  defp percent_cost_base(%{unit: %Unit{base_mana: base_mana}}, @mana_power_type)
       when is_integer(base_mana) and base_mana > 0, do: base_mana

  defp percent_cost_base(%{unit: %Unit{} = unit}, power_type) do
    Map.get(unit, Map.get(@max_power_fields, power_type, :max_power1)) || 0
  end

  defp percent_cost_base(_entity, _power_type), do: 0

  defp do_spend(%{unit: %Unit{health: health} = unit} = entity, @health_power_type, cost, _now)
       when is_integer(cost) and cost > 0 and is_integer(health) do
    %{entity | unit: %{unit | health: max(health - cost, 1)}}
    |> Core.mark_broadcast_update()
  end

  defp do_spend(entity, power_type, cost, now) when is_integer(cost) and cost > 0 do
    entity
    |> deduct_power(Map.get(@power_fields, power_type), cost)
    |> track_mana_use(power_type, now)
  end

  defp do_spend(entity, _power_type, _cost, _now), do: entity

  defp deduct_power(%{unit: %Unit{} = unit} = entity, field, cost) when is_atom(field) do
    case Map.get(unit, field) do
      power when is_integer(power) and power > 0 ->
        %{entity | unit: Map.put(unit, field, max(power - cost, 0))}
        |> Core.mark_broadcast_update()

      _ ->
        entity
    end
  end

  defp deduct_power(entity, _field, _cost), do: entity

  defp track_mana_use(%{internal: %Internal{} = internal} = entity, @mana_power_type, now) do
    %{entity | internal: %{internal | last_mana_use_at: now}}
  end

  defp track_mana_use(entity, _power_type, _now), do: entity

  def refund_power(entity, %Spell{power_type: power_type} = spell, fraction)
      when is_number(fraction) and fraction > 0 do
    gain_power(entity, power_type, round(power_cost(entity, spell) * fraction))
  end

  def refund_power(entity, _spell, _fraction), do: entity

  def rage_conversion(level) when is_integer(level) and level > 0 do
    0.0091107836 * level * level + 3.225598133 * level + 4.2652911
  end

  def rage_conversion(_level), do: rage_conversion(1)

  def gain_attack_rage(%{unit: %Unit{power_type: @rage_power_type, level: level}} = entity, damage, :dealt)
      when is_number(damage) and damage > 0 do
    gain_rage(entity, damage / rage_conversion(level) * @rage_dealt_factor * 10)
  end

  def gain_attack_rage(%{unit: %Unit{power_type: @rage_power_type, level: level}} = entity, damage, :taken)
      when is_number(damage) and damage > 0 do
    rage = damage / rage_conversion(level) * @rage_taken_factor * 10
    gain_rage(entity, rage * taken_rage_multiplier(entity))
  end

  def gain_attack_rage(entity, _damage, _kind), do: entity

  defp taken_rage_multiplier(entity) do
    if Aura.has_spell?(entity, @berserker_rage_spell_id) do
      @berserker_rage_taken_multiplier
    else
      1.0
    end
  end

  def gain_rage(
        %{unit: %Unit{power_type: @rage_power_type, power2: rage, max_power2: max_rage} = unit} = entity,
        amount
      )
      when is_integer(max_rage) and max_rage > 0 and is_number(amount) and amount > 0 do
    rage = if is_number(rage), do: rage, else: 0
    new_rage = min(rage + trunc(amount), max_rage)

    if new_rage == rage do
      entity
    else
      %{entity | unit: %{unit | power2: new_rage}}
      |> Core.mark_broadcast_update()
    end
  end

  def gain_rage(entity, _amount), do: entity

  def drain_rage(%{unit: %Unit{power_type: @rage_power_type, power2: rage} = unit} = entity)
      when is_integer(rage) and rage > 0 do
    %{entity | unit: %{unit | power2: 0}}
    |> Core.mark_broadcast_update()
  end

  def drain_rage(entity), do: entity

  def gain_power(%{unit: %Unit{} = unit} = entity, power_type, amount)
      when is_integer(power_type) and is_number(amount) and amount > 0 do
    field = Map.get(@power_fields, power_type)
    max_field = Map.get(@max_power_fields, power_type)

    with true <- is_atom(field) and is_atom(max_field),
         max_power when is_integer(max_power) and max_power > 0 <- Map.get(unit, max_field) do
      power = Map.get(unit, field)
      power = if is_integer(power), do: power, else: 0
      new_power = min(power + trunc(amount), max_power)

      if new_power == power do
        entity
      else
        %{entity | unit: Map.put(unit, field, new_power)}
        |> Core.mark_broadcast_update()
      end
    else
      _ -> entity
    end
  end

  def gain_power(entity, _power_type, _amount), do: entity
end
