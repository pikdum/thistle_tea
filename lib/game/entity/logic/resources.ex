defmodule ThistleTea.Game.Entity.Logic.Resources do
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core

  @rage_power_type 1
  @rage_per_damage 10

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
