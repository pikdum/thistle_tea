defmodule ThistleTea.Game.Spell.Modifiers do
  @moduledoc """
  Applies DBC flat and percent spell modifiers to spells selected by their
  spell-family masks.
  """
  import Bitwise, only: [&&&: 2, |||: 2, <<<: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  @modifier_types [:add_flat_modifier, :add_pct_modifier]
  @periodic_auras [:periodic_damage, :periodic_heal, :periodic_leech, :periodic_health_funnel, :periodic_mana_leech]

  @aura_operations %{
    mod_attack_power: :attack_power,
    mod_ranged_attack_power: :attack_power,
    mod_attack_power_pct: :attack_power,
    mod_ranged_attack_power_pct: :attack_power,
    mod_attack_speed: :haste,
    mod_casting_speed: :haste,
    mod_melee_haste: :haste,
    mod_ranged_haste: :haste
  }

  @operations %{
    0 => :damage,
    1 => :duration,
    2 => :threat,
    3 => :attack_power,
    4 => :charges,
    5 => :range,
    6 => :radius,
    7 => :critical_chance,
    8 => :all_effects,
    9 => :not_lose_casting_time,
    10 => :casting_time,
    11 => :cooldown,
    12 => :speed,
    14 => :cost,
    15 => :crit_damage_bonus,
    16 => :resist_miss_chance,
    17 => :jump_targets,
    18 => :chance_of_success,
    19 => :activation_time,
    20 => :effect_past_first,
    21 => :global_cooldown,
    22 => :dot,
    23 => :haste,
    24 => :spell_bonus_damage,
    27 => :multiple_value,
    28 => :resist_dispel_chance
  }

  def operation(value) when is_integer(value), do: Map.get(@operations, value, value)
  def operation(value), do: value

  def value(entity, %Spell{} = spell, operation, base) when is_number(base) do
    entity
    |> snapshot(spell)
    |> value(operation, base)
  end

  def value(_entity, _spell, _operation, base), do: base

  def value(modifiers, operation, base) when is_list(modifiers) and is_number(base) do
    modifiers = Enum.filter(modifiers, &(operation(&1.misc_value) == operation))
    flat = modifier_total(modifiers, :add_flat_modifier)
    percent = modifier_total(modifiers, :add_pct_modifier)
    (base + flat) * max(100 + percent, 0) / 100
  end

  def value(_modifiers, _operation, base), do: base

  def aura_amount(modifiers, %Effect{aura: type}, amount) do
    case Map.fetch(@aura_operations, type) do
      {:ok, operation} -> value(modifiers, operation, amount)
      :error -> amount
    end
  end

  def periodic_interval(modifiers, %Effect{} = effect) do
    period = Effect.period_ms(effect)

    if Effect.periodic?(effect) and is_integer(period) and period > 0,
      do: max(trunc(value(modifiers, :activation_time, period)), 1),
      else: period
  end

  def snapshot(entity, %Spell{} = spell), do: entity |> snapshot_all() |> for_spell(spell)
  def snapshot(_entity, _spell), do: []

  def snapshot_all(%{unit: %{auras: holders}} = entity) when is_list(holders) do
    for %Holder{spell: %Spell{spell_family: family}} = holder <- holders ++ inherited_holders(entity),
        is_integer(family) and family > 0,
        %Aura{type: type, amount: amount} = aura <- holder.auras,
        type in @modifier_types,
        is_number(amount),
        do: {family, %{aura | amount: amount * holder_stacks(holder)}}
  end

  def snapshot_all(_entity), do: []

  def for_spell(snapshot, %Spell{spell_family: family} = spell) when is_list(snapshot) do
    for {^family, %Aura{} = aura} <- snapshot, class_mask_applies?(aura.class_mask, spell), do: aura
  end

  def for_spell(_snapshot, _spell), do: []

  def holders(%{unit: %{auras: holders}}), do: holders(holders)

  def holders(holders) when is_list(holders) do
    Enum.flat_map(holders, fn %Holder{} = holder ->
      case Enum.filter(holder.auras, &(&1.type in @modifier_types)) do
        [] -> []
        modifiers -> [%{holder | auras: modifiers}]
      end
    end)
  end

  def holders(_entity), do: []

  defp inherited_holders(%{internal: %{pet: %{owner_spell_modifiers: holders}}}), do: holders
  defp inherited_holders(%{internal: %{totem: %{owner_spell_modifiers: holders}}}), do: holders
  defp inherited_holders(_entity), do: []

  defp holder_stacks(%Holder{stacks: stacks}) when is_integer(stacks) and stacks > 1, do: stacks
  defp holder_stacks(_holder), do: 1

  def integer_value(entity, %Spell{} = spell, operation, base) when is_number(base) do
    entity
    |> value(spell, operation, base)
    |> round()
    |> max(0)
  end

  def integer_value(_entity, _spell, _operation, base), do: base

  def consumable_holder_ids(%{unit: %{auras: holders}}, %Spell{} = spell) when is_list(holders) do
    for %Holder{spell: %Spell{id: id}, charges: charges} = holder <- holders,
        is_integer(charges) and charges > 0,
        holder_used_by_spell?(holder, spell),
        do: id
  end

  def consumable_holder_ids(_entity, _spell), do: []

  defp modifier_total(modifiers, type) do
    Enum.reduce(modifiers, 0, fn
      %Aura{type: ^type, amount: amount}, total -> total + amount
      _aura, total -> total
    end)
  end

  defp modifier_applies?(%Spell{spell_family: family}, %Spell{spell_family: family})
       when is_integer(family) and family > 0 do
    true
  end

  defp modifier_applies?(_modifier, _spell), do: false

  defp class_mask_applies?(mask, %Spell{} = spell) when is_integer(mask) do
    flags = (spell.family_flags_0 || 0) ||| (spell.family_flags_1 || 0) <<< 32
    (mask &&& flags) != 0
  end

  defp class_mask_applies?(_mask, _spell), do: false

  defp holder_used_by_spell?(%Holder{} = holder, %Spell{} = spell) do
    modifier_applies?(holder.spell, spell) and
      Enum.any?(holder.auras, &(class_mask_applies?(&1.class_mask, spell) and modifier_used_by_spell?(&1, spell)))
  end

  defp modifier_used_by_spell?(%Aura{type: type, misc_value: misc}, %Spell{} = spell) when type in @modifier_types do
    operation_used_by_spell?(operation(misc), spell)
  end

  defp modifier_used_by_spell?(_aura, _spell), do: false

  defp operation_used_by_spell?(:cost, %Spell{} = spell) do
    (spell.mana_cost || 0) > 0 or (spell.mana_cost_percent || 0) > 0
  end

  defp operation_used_by_spell?(:casting_time, %Spell{cast_time_ms: cast_time_ms}),
    do: is_integer(cast_time_ms) and cast_time_ms > 0

  defp operation_used_by_spell?(:critical_chance, %Spell{} = spell), do: critical_spell?(spell)
  defp operation_used_by_spell?(:damage, %Spell{} = spell), do: Spell.damage_effects(spell) != []
  defp operation_used_by_spell?(:all_effects, %Spell{effects: effects}), do: Enum.any?(effects, &effectful?/1)

  defp operation_used_by_spell?(operation, %Spell{effects: effects}) when operation in [:attack_power, :haste] do
    Enum.any?(effects, &(Map.get(@aura_operations, &1.aura) == operation))
  end

  defp operation_used_by_spell?(:speed, %Spell{effects: effects}) do
    Enum.any?(effects, &(&1.aura in [:mod_increase_speed, :mod_decrease_speed, :mod_increase_swim_speed]))
  end

  defp operation_used_by_spell?(:duration, %Spell{duration_ms: duration}), do: is_integer(duration) and duration > 0

  defp operation_used_by_spell?(:global_cooldown, %Spell{gcd_category: category, gcd_ms: duration}),
    do: category > 0 or (is_integer(duration) and duration > 0)

  defp operation_used_by_spell?(:activation_time, %Spell{effects: effects}) do
    Enum.any?(effects, fn effect ->
      period = Effect.period_ms(effect)
      Effect.periodic?(effect) and is_integer(period) and period > 0
    end)
  end

  defp operation_used_by_spell?(:radius, %Spell{effects: effects}) do
    Enum.any?(effects, &(is_number(&1.radius_yards) and &1.radius_yards > 0))
  end

  defp operation_used_by_spell?(:cooldown, %Spell{} = spell) do
    (spell.recovery_time_ms || 0) > 0 or (spell.category_recovery_time_ms || 0) > 0
  end

  defp operation_used_by_spell?(:dot, %Spell{effects: effects}) do
    Enum.any?(effects, &(&1.aura in @periodic_auras))
  end

  defp operation_used_by_spell?(:multiple_value, %Spell{effects: effects}) do
    Enum.any?(effects, &(&1.aura in [:periodic_leech, :periodic_health_funnel]))
  end

  defp operation_used_by_spell?(operation, %Spell{effects: effects})
       when operation in [:jump_targets, :effect_past_first] do
    Enum.any?(effects, &(is_integer(&1.chain_targets) and &1.chain_targets > 0))
  end

  defp operation_used_by_spell?(:crit_damage_bonus, %Spell{} = spell), do: critical_spell?(spell)
  defp operation_used_by_spell?(:resist_miss_chance, %Spell{} = spell), do: Spell.harmful?(spell)

  defp operation_used_by_spell?(_operation, _spell), do: false

  defp critical_spell?(%Spell{effects: effects} = spell) do
    Spell.damage_effects(spell) != [] or Enum.any?(effects, &match?(%Effect{type: :heal}, &1))
  end

  defp effectful?(%Effect{type: type, aura: aura}) when type in [:apply_aura, :apply_area_aura] do
    aura in @periodic_auras
  end

  defp effectful?(%Effect{type: type}) do
    type in [
      :school_damage,
      :heal,
      :health_leech,
      :weapon_damage,
      :weapon_damage_noschool,
      :normalized_weapon_damage,
      :weapon_percent_damage
    ]
  end

  defp effectful?(_effect), do: false
end
