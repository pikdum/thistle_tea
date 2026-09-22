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
  alias ThistleTea.Game.Entity.Logic.AttackPower
  alias ThistleTea.Game.Entity.Logic.Disarm
  alias ThistleTea.Game.Entity.Logic.PetHappiness
  alias ThistleTea.Game.Entity.Logic.WeaponDamage
  alias ThistleTea.Game.Spell

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
    |> derive_max_energy()
    |> derive_attack_power()
    |> derive_weapon_damage()
    |> derive_happiness_damage()
  end

  defp derive_happiness_damage(%Unit{base_min_damage: base_min, base_max_damage: base_max} = unit)
       when is_number(base_min) and is_number(base_max) do
    multiplier = PetHappiness.damage_multiplier(unit)

    if multiplier == 1.0 do
      unit
    else
      %{unit | min_damage: unit.min_damage * multiplier, max_damage: unit.max_damage * multiplier}
    end
  end

  defp derive_happiness_damage(%Unit{} = unit), do: unit

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

  def melee_attack_power(class, level, strength, agility),
    do: max(stat_melee_attack_power(class, level, strength, agility), 0)

  defp stat_melee_attack_power(class, level, strength, agility) do
    case class do
      @warrior -> level * 3 + strength * 2 - 20
      @paladin -> level * 3 + strength * 2 - 20
      @rogue -> level * 2 + strength + agility - 20
      @hunter -> level * 2 + strength + agility - 20
      @shaman -> level * 2 + strength * 2 - 20
      @druid -> strength * 2 - 20
      _ -> strength - 10
    end
  end

  def ranged_attack_power(class, level, agility), do: max(stat_ranged_attack_power(class, level, agility), 0)

  defp stat_ranged_attack_power(class, level, agility) do
    case class do
      @hunter -> level * 2 + agility * 2 - 10
      @rogue -> level + agility - 10
      @warrior -> level + agility - 10
      _ -> agility - 10
    end
  end

  defp derive_stats(%Unit{} = unit) do
    Enum.reduce(@stat_fields, unit, fn {index, field, base_field, bonus_key}, acc ->
      case Map.get(acc, base_field) do
        base when is_integer(base) ->
          scaled = (base + equipment_bonus(acc, bonus_key)) * aura_stat_multiplier(acc, index, :mod_percent_stat)
          value = (scaled + aura_stat_bonus(acc, index)) * aura_stat_multiplier(acc, index, :mod_total_stat_percent)
          struct!(acc, [{field, trunc(value)}])

        _ ->
          acc
      end
    end)
  end

  defp derive_resistances(%Unit{} = unit) do
    Enum.reduce(@resistance_fields, unit, fn {bit, field, base_field, bonus_key}, acc ->
      base = Map.get(acc, base_field) || 0
      base_and_equipment = base + equipment_bonus(acc, bonus_key)
      scaled = trunc(base_and_equipment * aura_base_resistance_multiplier(acc, bit))
      total = scaled + stat_armor(acc, bit) + aura_resistance_bonus(acc, bit) + aura_stat_resistance_bonus(acc, bit)
      Map.put(acc, field, trunc(total * aura_resistance_multiplier(acc, bit)))
    end)
  end

  defp stat_armor(%Unit{stat_model: :creature, agility: agility}, 0x01), do: agility || 0
  defp stat_armor(_unit, _bit), do: 0

  defp aura_stat_resistance_bonus(%Unit{} = unit, bit) do
    intellect = unit.intellect || 0

    sum_aura_amounts(unit, fn
      %Aura{type: :mod_resistance_of_stat_percent, amount: amount, misc_value: mask}
      when is_integer(amount) and is_integer(mask) and (mask &&& bit) != 0 ->
        div(intellect * amount, 100)

      _aura ->
        0
    end)
  end

  defp derive_max_health(%Unit{base_health: base_health} = unit) when is_integer(base_health) do
    flat =
      base_health + stamina_health(unit) + equipment_bonus(unit, :health) +
        aura_max_health(unit)

    max_health = max(trunc(flat * aura_power_multiplier(unit, :mod_increase_health_percent, -1)), 1)

    %{unit | max_health: max_health, health: clamp(unit.health, max_health)}
  end

  defp derive_max_health(%Unit{} = unit), do: unit

  defp stamina_health(%Unit{stat_model: :creature} = unit), do: ((unit.stamina || 0) - (unit.base_stamina || 0)) * 10
  defp stamina_health(%Unit{} = unit), do: stamina_health_bonus(unit.stamina || 0)

  @power_type_mana 0
  @power_type_energy 3

  defp derive_max_mana(%Unit{base_mana: base_mana, stat_model: model} = unit)
       when is_integer(base_mana) and (base_mana > 0 or model == :creature) do
    flat =
      base_mana + intellect_mana(unit) + equipment_bonus(unit, :mana) +
        aura_power_bonus(unit, @power_type_mana)

    max_mana = max(trunc(flat * aura_power_multiplier(unit, :mod_increase_energy_percent, @power_type_mana)), 0)
    %{unit | max_power1: max_mana, power1: clamp(unit.power1, max_mana)}
  end

  defp derive_max_mana(%Unit{} = unit), do: unit

  defp intellect_mana(%Unit{stat_model: :creature} = unit),
    do: ((unit.intellect || 0) - (unit.base_intellect || 0)) * 15

  defp intellect_mana(%Unit{} = unit), do: mana_bonus(unit.intellect || 0)

  @base_max_energy 100

  defp derive_max_energy(%Unit{base_health: base_health, power_type: @power_type_energy} = unit)
       when is_integer(base_health) do
    flat = @base_max_energy + aura_power_bonus(unit, @power_type_energy)
    max_energy = max(trunc(flat * aura_power_multiplier(unit, :mod_increase_energy_percent, @power_type_energy)), 0)
    %{unit | max_power4: max_energy, power4: clamp(unit.power4, max_energy)}
  end

  defp derive_max_energy(%Unit{} = unit), do: unit

  defp aura_power_bonus(%Unit{} = unit, power_type) do
    sum_aura_amounts(unit, fn
      %Aura{type: :mod_increase_energy, amount: amount, misc_value: ^power_type} when is_integer(amount) -> amount
      _aura -> 0
    end)
  end

  defp aura_power_multiplier(%Unit{auras: holders}, type, power_type) when is_list(holders) do
    for %Holder{auras: auras} <- holders,
        %Aura{type: ^type, amount: amount, misc_value: misc} <- auras,
        is_number(amount),
        power_type == -1 or misc == power_type,
        reduce: 1.0 do
      acc -> acc * (100 + amount) / 100
    end
  end

  defp aura_power_multiplier(_unit, _type, _power_type), do: 1.0

  defp derive_attack_power(%Unit{base_attack_power: base} = unit) when is_number(base) do
    melee = base + creature_stat_attack_power(unit, :melee)
    ranged = (unit.base_ranged_attack_power || 0) + creature_stat_attack_power(unit, :ranged)

    %{
      unit
      | attack_power: AttackPower.total(unit, melee, :melee),
        ranged_attack_power: AttackPower.total(unit, ranged, :ranged)
    }
  end

  defp derive_attack_power(%Unit{base_strength: base_strength} = unit) when is_integer(base_strength) do
    %{
      unit
      | attack_power: AttackPower.total(unit, unit_attack_power(unit), :melee),
        ranged_attack_power:
          AttackPower.total(unit, ranged_attack_power(unit.class, unit.level, unit.agility || 0), :ranged)
    }
  end

  defp derive_attack_power(%Unit{} = unit), do: unit

  defp creature_stat_attack_power(%Unit{attack_power_model: model} = unit, kind)
       when model in [:hunter_pet, :summoned_pet, :imp] do
    if kind == :melee, do: AttackPower.pet_base(unit) - unit.base_attack_power, else: 0
  end

  defp creature_stat_attack_power(%Unit{base_strength: strength, base_agility: agility} = unit, kind)
       when is_integer(strength) and is_integer(agility) do
    level = unit.level || 1

    if kind == :ranged do
      stat_ranged_attack_power(unit.class, level, unit.agility) -
        stat_ranged_attack_power(unit.class, level, agility)
    else
      stat_melee_attack_power(unit.class, level, unit.strength, unit.agility) -
        stat_melee_attack_power(unit.class, level, strength, agility)
    end
  end

  defp creature_stat_attack_power(_unit, _kind), do: 0

  defp unit_attack_power(%Unit{max_power5: capacity, strength: strength}) when is_integer(capacity) and capacity > 0 do
    max(strength * 2 - 20, 0)
  end

  defp unit_attack_power(%Unit{class: @druid, shapeshift_form: 1} = unit) do
    max((unit.strength || 0) * 2 + (unit.agility || 0) - 20, 0) + predatory_strikes_bonus(unit)
  end

  defp unit_attack_power(%Unit{class: @druid, shapeshift_form: form} = unit) when form in [5, 8] do
    melee_attack_power(unit.class, unit.level, unit.strength || 0, unit.agility || 0) +
      predatory_strikes_bonus(unit)
  end

  defp unit_attack_power(%Unit{} = unit) do
    melee_attack_power(unit.class, unit.level, unit.strength || 0, unit.agility || 0)
  end

  @predatory_strikes [16_972, 16_974, 16_975]

  defp predatory_strikes_bonus(%Unit{auras: holders} = unit) when is_list(holders) do
    level = unit.level || 1

    pct =
      Enum.find_value(holders, 0, fn
        %Holder{spell: %Spell{id: id}, auras: auras} when id in @predatory_strikes ->
          Enum.find_value(auras, fn
            %Aura{type: :dummy, amount: amount} when is_integer(amount) -> amount
            _aura -> nil
          end)

        _holder ->
          nil
      end)

    div(level * pct, 100)
  end

  defp predatory_strikes_bonus(_unit), do: 0

  defp derive_weapon_damage(%Unit{} = unit) do
    unit
    |> derive_melee_attack_time()
    |> derive_ranged_attack_time()
    |> derive_mainhand_damage()
    |> derive_damage(
      :base_offhand_min_damage,
      :base_offhand_max_damage,
      :min_offhand_damage,
      :max_offhand_damage,
      unit.offhand_attack_time
    )
    |> derive_ranged_damage()
  end

  defp derive_melee_attack_time(%Unit{class: @druid, shapeshift_form: 1} = unit), do: %{unit | base_attack_time: 1_000}

  defp derive_melee_attack_time(%Unit{class: @druid, shapeshift_form: form} = unit) when form in [5, 8],
    do: %{unit | base_attack_time: 2_500}

  defp derive_melee_attack_time(%Unit{base_melee_attack_time: base} = unit) when is_number(base) and base > 0 do
    unarmed? = not AttackPower.creature?(unit) and Disarm.unarmed?(unit)
    %{unit | base_attack_time: if(unarmed?, do: 2_000, else: base)}
  end

  defp derive_melee_attack_time(%Unit{} = unit), do: unit

  defp derive_ranged_attack_time(%Unit{base_ranged_attack_time: base} = unit) when is_number(base) and base > 0 do
    haste = max(equipment_bonus(unit, :ranged_haste) + aura_ranged_haste(unit), 0)
    %{unit | ranged_attack_time: trunc(base * 100 / (100 + haste))}
  end

  defp derive_ranged_attack_time(%Unit{} = unit), do: unit

  defp aura_ranged_haste(%Unit{} = unit) do
    sum_aura_amounts(unit, fn
      %Aura{type: :mod_ranged_haste, amount: amount} when is_integer(amount) -> amount
      _aura -> 0
    end)
  end

  defp derive_ranged_damage(%Unit{} = unit) do
    with base_min when is_number(base_min) <- unit.base_ranged_min_damage,
         base_max when is_number(base_max) <- unit.base_ranged_max_damage do
      {base_min, base_max, bonus} = ranged_damage_inputs(unit, base_min, base_max)

      multiplier =
        if WeaponDamage.wand?(unit.ranged_weapon),
          do: WeaponDamage.multiplier(%{unit: unit}, unit.ranged_weapon.dmg_type1, unit.ranged_weapon),
          else: 1.0

      %{unit | min_ranged_damage: (base_min + bonus) * multiplier, max_ranged_damage: (base_max + bonus) * multiplier}
    else
      _ -> unit
    end
  end

  defp ranged_damage_inputs(%Unit{} = unit, base_min, base_max) do
    if AttackPower.creature?(unit) do
      multiplier = AttackPower.creature_multiplier(unit, :ranged)
      {base_min * multiplier, base_max * multiplier, equipment_bonus(unit, :ranged_damage)}
    else
      bonus =
        attack_power_bonus(WeaponDamage.ranged_attack_power(unit), unit.ranged_attack_time) +
          equipment_bonus(unit, :ranged_damage)

      {base_min, base_max, bonus}
    end
  end

  defp derive_mainhand_damage(%Unit{class: @druid, shapeshift_form: form} = unit) when form in [1, 5, 8] do
    speed = (unit.base_attack_time || 2000) / 1000
    level = min(unit.level || 1, 60)
    bonus = attack_power_bonus(unit.attack_power, unit.base_attack_time)
    %{unit | min_damage: level * 0.85 * speed + bonus, max_damage: level * 1.25 * speed + bonus}
  end

  defp derive_mainhand_damage(%Unit{} = unit) do
    if not AttackPower.creature?(unit) and is_number(unit.base_melee_attack_time) and Disarm.unarmed?(unit) do
      bonus = attack_power_bonus(unit.attack_power, unit.base_attack_time)
      %{unit | min_damage: 1.0 + bonus, max_damage: 2.0 + bonus}
    else
      derive_damage(unit, :base_min_damage, :base_max_damage, :min_damage, :max_damage, unit.base_attack_time)
    end
  end

  defp derive_damage(%Unit{} = unit, base_min_field, base_max_field, min_field, max_field, attack_time) do
    with base_min when is_number(base_min) <- Map.get(unit, base_min_field),
         base_max when is_number(base_max) <- Map.get(unit, base_max_field) do
      key = if min_field == :min_offhand_damage, do: :offhand_damage, else: :mainhand_damage
      {base_min, base_max, bonus} = melee_damage_inputs(unit, base_min, base_max, attack_time, key)

      struct!(unit, [{min_field, base_min + bonus}, {max_field, base_max + bonus}])
    else
      _ -> unit
    end
  end

  defp melee_damage_inputs(unit, base_min, base_max, attack_time, key) do
    if AttackPower.creature?(unit) do
      multiplier = AttackPower.creature_multiplier(unit, :melee)
      {base_min * multiplier, base_max * multiplier, equipment_bonus(unit, key)}
    else
      {base_min, base_max, attack_power_bonus(unit.attack_power, attack_time) + equipment_bonus(unit, key)}
    end
  end

  defp attack_power_bonus(attack_power, attack_time)
       when is_integer(attack_power) and attack_power > 0 and is_number(attack_time) and attack_time > 0 do
    attack_power / 14 * (attack_time / 1000)
  end

  defp attack_power_bonus(_attack_power, _attack_time), do: 0.0

  defp clamp(current, max) when is_number(current) and current > max, do: max
  defp clamp(current, _max), do: current

  defp equipment_bonus(%Unit{equipment_bonuses: %{} = bonuses}, key), do: Map.get(bonuses, key, 0)
  defp equipment_bonus(%Unit{}, _key), do: 0

  defp aura_max_health(%Unit{} = unit) do
    sum_aura_amounts(unit, fn
      %Aura{type: :mod_increase_health, amount: amount} when is_integer(amount) -> amount
      _aura -> 0
    end)
  end

  defp aura_stat_bonus(%Unit{} = unit, index) do
    sum_aura_amounts(unit, fn
      %Aura{type: :mod_stat, amount: amount, misc_value: misc}
      when is_integer(amount) and (misc == -1 or misc == index) ->
        amount

      _aura ->
        0
    end)
  end

  defp aura_stat_multiplier(%Unit{auras: holders}, index, type) when is_list(holders) do
    for %Holder{auras: auras, stacks: stacks} <- holders,
        %Aura{type: ^type, amount: amount, misc_value: misc} <- auras,
        is_integer(amount) and (misc == -1 or misc == index),
        reduce: 1.0 do
      multiplier -> multiplier * max(100 + amount * max(stacks || 1, 1), 0) / 100
    end
  end

  defp aura_stat_multiplier(_unit, _index, _type), do: 1.0

  defp aura_resistance_bonus(%Unit{} = unit, bit) do
    additive_resistance_bonus(unit, bit) + exclusive_resistance_bonus(unit, bit)
  end

  defp additive_resistance_bonus(unit, bit) do
    sum_aura_amounts(unit, fn
      %Aura{type: :mod_resistance, amount: amount, misc_value: mask}
      when is_integer(amount) and is_integer(mask) and (mask &&& bit) != 0 ->
        amount

      _aura ->
        0
    end)
  end

  defp exclusive_resistance_bonus(%Unit{auras: holders}, bit) when is_list(holders) do
    amounts =
      for %Holder{auras: auras, stacks: stacks} <- holders,
          %Aura{type: :mod_resistance_exclusive, amount: amount, misc_value: mask} <- auras,
          is_integer(amount) and is_integer(mask) and (mask &&& bit) != 0,
          do: amount * if(is_integer(stacks) and stacks > 1, do: stacks, else: 1)

    Enum.max([0 | amounts]) + Enum.min([0 | amounts])
  end

  defp exclusive_resistance_bonus(_unit, _bit), do: 0

  defp aura_base_resistance_multiplier(%Unit{} = unit, bit) do
    percent =
      sum_aura_amounts(unit, fn
        %Aura{type: :mod_base_resistance_percent, amount: amount, misc_value: mask}
        when is_integer(amount) and is_integer(mask) and (mask &&& bit) != 0 ->
          amount

        _aura ->
          0
      end)

    max(100 + percent, 0) / 100
  end

  defp aura_resistance_multiplier(%Unit{} = unit, bit) do
    percent =
      sum_aura_amounts(unit, fn
        %Aura{type: :mod_resistance_percent, amount: amount, misc_value: mask}
        when is_integer(amount) and is_integer(mask) and (mask &&& bit) != 0 ->
          amount

        _aura ->
          0
      end)

    max(100 + percent, 0) / 100
  end

  defp sum_aura_amounts(%Unit{auras: holders}, fun) when is_list(holders) do
    Enum.reduce(holders, 0, fn %Holder{auras: auras} = holder, acc ->
      stacks = if is_integer(holder.stacks) and holder.stacks > 1, do: holder.stacks, else: 1
      Enum.reduce(auras, acc, &(fun.(&1) * stacks + &2))
    end)
  end

  defp sum_aura_amounts(%Unit{}, _fun), do: 0
end
