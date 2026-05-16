defmodule ThistleTea.Game.Entity.Logic.Combat do
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Math

  @default_attack_speed_ms 2000
  @default_damage 2

  def attack_speed_ms(%{unit: %Unit{base_attack_time: attack_time}}) when is_integer(attack_time) and attack_time > 0 do
    attack_time
  end

  def attack_speed_ms(_entity), do: @default_attack_speed_ms

  def damage_range(%{unit: %Unit{min_damage: min_damage, max_damage: max_damage}})
      when is_number(min_damage) and is_number(max_damage) do
    {min_damage, max_damage}
  end

  def damage_range(_entity), do: {@default_damage, @default_damage}

  def attack_damage(%{damage: damage}) when is_number(damage), do: trunc(damage)

  def attack_damage(%{min_damage: min_damage, max_damage: max_damage})
      when is_number(min_damage) and is_number(max_damage) do
    min_value = min(min_damage, max_damage)
    max_value = max(min_damage, max_damage)
    Math.random_int(min_value, max_value)
  end

  def attack_damage(_attack), do: @default_damage

  def attack_start(attacker, target) when is_integer(attacker) and is_integer(target) do
    Event.attack_start(attacker, target)
  end

  def attacker_state_update(attacker, target, damage, attack \\ %{}) when is_integer(attacker) and is_integer(target) do
    Event.attacker_state_update(attacker, target, damage, attack)
  end
end
