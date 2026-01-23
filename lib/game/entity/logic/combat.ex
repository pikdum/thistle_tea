defmodule ThistleTea.Game.Entity.Logic.Combat do
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Network.Message

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
    %Message.SmsgAttackstart{attacker: attacker, victim: target}
  end

  def attacker_state_update(attacker, target, damage, attack \\ %{}) when is_integer(attacker) and is_integer(target) do
    %Message.SmsgAttackerstateupdate{
      attacker: attacker,
      target: target,
      hit_info: Map.get(attack, :hit_info, 0x2),
      total_damage: damage,
      damages: [
        %{
          spell_school_mask: Map.get(attack, :spell_school_mask, 0),
          damage_float: damage * 1.0,
          damage_uint: damage,
          absorb: Map.get(attack, :absorb, 0),
          resist: Map.get(attack, :resist, 0)
        }
      ],
      damage_state: Map.get(attack, :damage_state, 0),
      unknown1: Map.get(attack, :unknown1, 0),
      spell_id: Map.get(attack, :spell_id, 0),
      blocked_amount: Map.get(attack, :blocked_amount, 0)
    }
  end
end
