defmodule ThistleTea.Game.Spell.Modifiers do
  @moduledoc """
  Applies DBC flat and percent spell modifiers to spells selected by their
  spell-family masks.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  @modifier_types [:add_flat_modifier, :add_pct_modifier]

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

  def snapshot(%{unit: %{auras: holders}}, %Spell{} = spell) when is_list(holders) do
    for %Holder{} = holder <- holders,
        modifier_applies?(holder.spell, spell),
        %Aura{type: type, amount: amount, class_mask: class_mask} = aura <- holder.auras,
        type in @modifier_types,
        is_number(amount),
        class_mask_applies?(class_mask, spell),
        do: aura
  end

  def snapshot(_entity, _spell), do: []

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

  defp class_mask_applies?(mask, %Spell{}) when mask in [0, nil], do: true

  defp class_mask_applies?(mask, %Spell{family_flags_0: flags}) when is_integer(mask), do: (mask &&& (flags || 0)) != 0

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

  defp operation_used_by_spell?(:speed, %Spell{effects: effects}) do
    Enum.any?(effects, &(&1.aura in [:mod_increase_speed, :mod_decrease_speed, :mod_increase_swim_speed]))
  end

  defp operation_used_by_spell?(:duration, %Spell{duration_ms: duration}), do: is_integer(duration) and duration > 0

  defp operation_used_by_spell?(:cooldown, %Spell{} = spell) do
    (spell.recovery_time_ms || 0) > 0 or (spell.category_recovery_time_ms || 0) > 0
  end

  defp operation_used_by_spell?(:dot, %Spell{effects: effects}) do
    Enum.any?(effects, &(&1.aura in [:periodic_damage, :periodic_heal, :periodic_leech, :periodic_mana_leech]))
  end

  defp operation_used_by_spell?(:crit_damage_bonus, %Spell{} = spell), do: critical_spell?(spell)
  defp operation_used_by_spell?(:resist_miss_chance, %Spell{} = spell), do: Spell.harmful?(spell)

  defp operation_used_by_spell?(_operation, _spell), do: false

  defp critical_spell?(%Spell{effects: effects} = spell) do
    Spell.damage_effects(spell) != [] or Enum.any?(effects, &match?(%Effect{type: :heal}, &1))
  end

  defp effectful?(%Effect{type: type, aura: aura}) when type in [:apply_aura, :apply_area_aura] do
    aura in [:periodic_damage, :periodic_heal, :periodic_leech, :periodic_mana_leech]
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
