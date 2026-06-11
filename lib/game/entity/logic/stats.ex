defmodule ThistleTea.Game.Entity.Logic.Stats do
  @moduledoc """
  Pure recompute of derived unit stats from the canonical inputs (`base_*`
  fields, equipment bonuses, active auras): displayed stats, resistances,
  health/mana maxima, attack power, and weapon damage. Fields whose base
  inputs are nil are skipped, which keeps mob DB values untouched.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit

  @resistance_fields [
    {0x01, :normal_resistance, :base_normal_resistance, :armor},
    {0x02, :holy_resistance, :base_holy_resistance, :holy},
    {0x04, :fire_resistance, :base_fire_resistance, :fire},
    {0x08, :nature_resistance, :base_nature_resistance, :nature},
    {0x10, :frost_resistance, :base_frost_resistance, :frost},
    {0x20, :shadow_resistance, :base_shadow_resistance, :shadow},
    {0x40, :arcane_resistance, :base_arcane_resistance, :arcane}
  ]

  @stat_fields [
    {0, :strength, :base_strength, :strength},
    {1, :agility, :base_agility, :agility},
    {2, :stamina, :base_stamina, :stamina},
    {3, :intellect, :base_intellect, :intellect},
    {4, :spirit, :base_spirit, :spirit}
  ]

  def recompute(%Unit{} = unit) do
    unit
    |> derive_stats()
    |> derive_resistances()
    |> derive_max_health()
    |> derive_max_mana()
    |> derive_attack_power()
    |> derive_weapon_damage()
  end

  def stamina_health_bonus(stamina) when stamina < 20, do: stamina
  def stamina_health_bonus(stamina), do: 20 + (stamina - 20) * 10

  def mana_bonus(intellect) when intellect < 20, do: intellect
  def mana_bonus(intellect), do: 20 + (intellect - 20) * 15

  @warrior 1
  @paladin 2
  @hunter 3
  @rogue 4
  @shaman 7
  @druid 11

  def melee_attack_power(class, level, strength, agility) do
    value =
      case class do
        @warrior -> level * 3 + strength * 2 - 20
        @paladin -> level * 3 + strength * 2 - 20
        @rogue -> level * 2 + strength + agility - 20
        @hunter -> level * 2 + strength + agility - 20
        @shaman -> level * 2 + strength * 2 - 20
        @druid -> strength * 2 - 20
        _ -> strength - 10
      end

    max(value, 0)
  end

  def ranged_attack_power(class, level, agility) do
    value =
      case class do
        @hunter -> level * 2 + agility * 2 - 10
        @rogue -> level + agility - 10
        @warrior -> level + agility - 10
        _ -> agility - 10
      end

    max(value, 0)
  end

  defp derive_stats(%Unit{} = unit) do
    Enum.reduce(@stat_fields, unit, fn {index, field, base_field, bonus_key}, acc ->
      case Map.get(acc, base_field) do
        base when is_integer(base) ->
          Map.put(acc, field, base + equipment_bonus(acc, bonus_key) + aura_stat_bonus(acc, index))

        _ ->
          acc
      end
    end)
  end

  defp derive_resistances(%Unit{} = unit) do
    Enum.reduce(@resistance_fields, unit, fn {bit, field, base_field, bonus_key}, acc ->
      base = Map.get(acc, base_field) || 0
      Map.put(acc, field, base + equipment_bonus(acc, bonus_key) + aura_resistance_bonus(acc, bit))
    end)
  end

  defp derive_max_health(%Unit{base_health: base_health} = unit) when is_integer(base_health) do
    max_health = max(base_health + stamina_health_bonus(unit.stamina || 0) + equipment_bonus(unit, :health), 1)
    %{unit | max_health: max_health, health: clamp(unit.health, max_health)}
  end

  defp derive_max_health(%Unit{} = unit), do: unit

  defp derive_max_mana(%Unit{base_mana: base_mana} = unit) when is_integer(base_mana) and base_mana > 0 do
    max_mana = max(base_mana + mana_bonus(unit.intellect || 0) + equipment_bonus(unit, :mana), 0)
    %{unit | max_power1: max_mana, power1: clamp(unit.power1, max_mana)}
  end

  defp derive_max_mana(%Unit{} = unit), do: unit

  defp derive_attack_power(%Unit{base_strength: base_strength} = unit) when is_integer(base_strength) do
    attack_power =
      melee_attack_power(unit.class, unit.level, unit.strength || 0, unit.agility || 0) +
        equipment_bonus(unit, :attack_power) + aura_attack_power(unit)

    %{
      unit
      | attack_power: attack_power,
        ranged_attack_power: ranged_attack_power(unit.class, unit.level, unit.agility || 0)
    }
  end

  defp derive_attack_power(%Unit{} = unit), do: unit

  defp derive_weapon_damage(%Unit{} = unit) do
    unit
    |> derive_damage(:base_min_damage, :base_max_damage, :min_damage, :max_damage, unit.base_attack_time)
    |> derive_damage(
      :base_offhand_min_damage,
      :base_offhand_max_damage,
      :min_offhand_damage,
      :max_offhand_damage,
      unit.offhand_attack_time
    )
  end

  defp derive_damage(%Unit{} = unit, base_min_field, base_max_field, min_field, max_field, attack_time) do
    with base_min when is_number(base_min) <- Map.get(unit, base_min_field),
         base_max when is_number(base_max) <- Map.get(unit, base_max_field) do
      bonus = attack_power_bonus(unit.attack_power, attack_time)

      unit
      |> Map.put(min_field, base_min + bonus)
      |> Map.put(max_field, base_max + bonus)
    else
      _ -> unit
    end
  end

  defp attack_power_bonus(attack_power, attack_time)
       when is_integer(attack_power) and attack_power > 0 and is_number(attack_time) and attack_time > 0 do
    attack_power / 14 * (attack_time / 1000)
  end

  defp attack_power_bonus(_attack_power, _attack_time), do: 0.0

  defp aura_attack_power(%Unit{} = unit) do
    sum_aura_amounts(unit, fn
      %Aura{type: :mod_attack_power, amount: amount} when is_integer(amount) -> amount
      _aura -> 0
    end)
  end

  defp clamp(current, max) when is_number(current) and current > max, do: max
  defp clamp(current, _max), do: current

  defp equipment_bonus(%Unit{equipment_bonuses: %{} = bonuses}, key), do: Map.get(bonuses, key, 0)
  defp equipment_bonus(%Unit{}, _key), do: 0

  defp aura_stat_bonus(%Unit{} = unit, index) do
    sum_aura_amounts(unit, fn
      %Aura{type: :mod_stat, amount: amount, misc_value: misc}
      when is_integer(amount) and (misc == -1 or misc == index) ->
        amount

      _aura ->
        0
    end)
  end

  defp aura_resistance_bonus(%Unit{} = unit, bit) do
    sum_aura_amounts(unit, fn
      %Aura{type: type, amount: amount, misc_value: mask}
      when type in [:mod_resistance, :mod_resistance_exclusive] and
             is_integer(amount) and is_integer(mask) and (mask &&& bit) != 0 ->
        amount

      _aura ->
        0
    end)
  end

  defp sum_aura_amounts(%Unit{auras: holders}, fun) when is_list(holders) do
    Enum.reduce(holders, 0, fn %Holder{auras: auras}, acc ->
      Enum.reduce(auras, acc, &(fun.(&1) + &2))
    end)
  end

  defp sum_aura_amounts(%Unit{}, _fun), do: 0
end
