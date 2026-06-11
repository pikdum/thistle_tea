defmodule ThistleTea.Game.Entity.Logic.Resources do
  @moduledoc """
  Spending and gaining unit power: spell power costs (marking the five-second
  rule) and rage generation from auto attacks. Rage is stored pre-scaled ×10,
  matching the client's units.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Spell

  @mana_power_type 0
  @rage_power_type 1
  @rage_per_damage 10

  @power_fields %{0 => :power1, 1 => :power2, 2 => :power3, 3 => :power4, 4 => :power5}

  def spend_power(entity, %Spell{mana_cost: cost, power_type: power_type}, now)
      when is_integer(cost) and cost > 0 and is_integer(now) do
    entity
    |> deduct_power(Map.get(@power_fields, power_type), cost)
    |> track_mana_use(power_type, now)
  end

  def spend_power(entity, _spell, _now), do: entity

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
    %{entity | internal: Map.put(internal, :last_mana_use_at, now)}
  end

  defp track_mana_use(entity, _power_type, _now), do: entity

  def gain_outgoing_auto_attack_rage(entity, %{queued_spell_id: spell_id}) when is_integer(spell_id) do
    entity
  end

  def gain_outgoing_auto_attack_rage(entity, attack) when is_map(attack) do
    attack
    |> rage_from_attack()
    |> then(&gain_rage(entity, &1))
  end

  def gain_outgoing_auto_attack_rage(entity, _attack), do: entity

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

  defp rage_from_attack(%{damage: damage}) when is_number(damage) and damage > 0 do
    max(trunc(damage * @rage_per_damage), 1)
  end

  defp rage_from_attack(_attack), do: 0
end
