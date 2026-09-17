defmodule ThistleTea.Game.Entity.Logic.Aura.Absorption do
  @moduledoc """
  Soaks incoming damage through school-absorb and mana-shield auras, draining
  their amounts (and mana for mana shields) and dropping exhausted holders.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Aura.Transition
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Modifiers

  @absorb_auras [:school_absorb, :mana_shield]

  def absorb_damage(%{unit: %Unit{auras: holders}} = entity, damage, school, now)
      when is_list(holders) and holders != [] and is_integer(damage) and damage > 0 and is_integer(now) do
    school_mask = Spell.school_mask(school)

    {entity, remaining, new_holders} =
      Enum.reduce(@absorb_auras, {entity, damage, holders}, fn type, {ent, dmg, current} ->
        {updated, {ent, dmg}} =
          Enum.map_reduce(current, {ent, dmg}, fn holder, {ent, dmg} ->
            absorb_with_holder(ent, dmg, holder, school_mask, type)
          end)

        {ent, dmg, updated}
      end)

    kept = Enum.reject(new_holders, &exhausted_absorb?/1)

    {entity, transition_events} =
      Transition.run(entity, %Change{holders: kept, cause: :consumed, now: now})

    {Effects.enqueue(entity, transition_events), remaining}
  end

  def absorb_damage(entity, damage, _school, _now), do: {entity, damage}

  defp absorb_with_holder(entity, damage, %Holder{auras: auras} = holder, school_mask, type) do
    {new_auras, {entity, damage}} =
      Enum.map_reduce(auras, {entity, damage}, fn aura, {ent, dmg} ->
        if absorbs?(aura, type, school_mask) and dmg > 0 do
          absorb_with_aura(ent, dmg, aura, holder.spell)
        else
          {aura, {ent, dmg}}
        end
      end)

    {%{holder | auras: new_auras}, {entity, damage}}
  end

  defp absorbs?(%Aura{type: type, amount: amount, misc_value: mask}, type, school_mask)
       when is_integer(amount) and amount > 0 and is_integer(mask), do: (mask &&& school_mask) != 0

  defp absorbs?(_aura, _type, _school_mask), do: false

  defp absorb_with_aura(entity, damage, %Aura{type: :school_absorb, amount: amount} = aura, _spell) do
    absorbed = min(amount, damage)
    {%{aura | amount: amount - absorbed}, {entity, damage - absorbed}}
  end

  defp absorb_with_aura(
         %{unit: %Unit{power1: mana}} = entity,
         damage,
         %Aura{type: :mana_shield, amount: amount} = aura,
         spell
       ) do
    multiplier = mana_multiplier(entity, spell, aura)
    mana = max(mana || 0, 0)
    capacity = if multiplier > 0, do: trunc(mana / multiplier), else: amount
    absorbed = min(min(amount, damage), capacity)
    spent = min(round(absorbed * multiplier), mana)
    entity = %{entity | unit: %{entity.unit | power1: mana - spent}}
    {%{aura | amount: amount - absorbed}, {entity, damage - absorbed}}
  end

  defp mana_multiplier(entity, spell, %Aura{multiple_value: multiple}) when is_number(multiple) and multiple > 0 do
    max(Modifiers.value(entity, spell, :multiple_value, multiple), 0)
  end

  defp mana_multiplier(_entity, _spell, _aura), do: 0

  defp exhausted_absorb?(%Holder{auras: auras}) do
    absorbs = Enum.filter(auras, fn %Aura{type: type} -> type in @absorb_auras end)
    absorbs != [] and Enum.all?(absorbs, fn %Aura{amount: amount} -> amount <= 0 end)
  end
end
