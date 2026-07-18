defmodule ThistleTea.Game.Entity.Logic.Aura.Absorption do
  @moduledoc """
  Soaks incoming damage through school-absorb and mana-shield auras, draining
  their amounts (and mana for mana shields) and dropping exhausted holders.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.HolderSync
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell

  @mana_per_absorbed_damage 2
  @absorb_auras [:school_absorb, :mana_shield]

  def absorb_damage(%{unit: %Unit{auras: holders}} = entity, damage, school)
      when is_list(holders) and holders != [] and is_integer(damage) and damage > 0 do
    school_mask = Spell.school_mask(school)

    {entity, remaining, new_holders} =
      Enum.reduce(holders, {entity, damage, []}, fn holder, {ent, dmg, acc} ->
        {ent, dmg, holder} = absorb_with_holder(ent, dmg, holder, school_mask)
        {ent, dmg, [holder | acc]}
      end)

    kept = new_holders |> Enum.reverse() |> Enum.reject(&exhausted_absorb?/1)

    entity =
      if kept == holders do
        entity
      else
        {entity, modifier_events} = HolderSync.sync(entity, kept)

        entity
        |> Event.enqueue(modifier_events)
        |> Core.mark_broadcast_update()
      end

    {entity, remaining}
  end

  def absorb_damage(entity, damage, _school), do: {entity, damage}

  defp absorb_with_holder(entity, damage, %Holder{auras: auras} = holder, school_mask) do
    {entity, damage, new_auras} =
      Enum.reduce(auras, {entity, damage, []}, fn aura, {ent, dmg, acc} ->
        {ent, dmg, aura} = absorb_with_aura(ent, dmg, aura, school_mask)
        {ent, dmg, [aura | acc]}
      end)

    {entity, damage, %{holder | auras: Enum.reverse(new_auras)}}
  end

  defp absorb_with_aura(entity, damage, %Aura{type: :school_absorb, amount: amount} = aura, school_mask)
       when damage > 0 and is_integer(amount) and amount > 0 do
    if (aura.misc_value &&& school_mask) == 0 do
      {entity, damage, aura}
    else
      absorbed = min(amount, damage)
      {entity, damage - absorbed, %{aura | amount: amount - absorbed}}
    end
  end

  defp absorb_with_aura(
         %{unit: %Unit{power1: mana}} = entity,
         damage,
         %Aura{type: :mana_shield, amount: amount} = aura,
         _school_mask
       )
       when damage > 0 and is_integer(amount) and amount > 0 and is_integer(mana) and mana > 0 do
    absorbed = min(min(amount, damage), div(mana, @mana_per_absorbed_damage))

    if absorbed > 0 do
      entity = %{entity | unit: %{entity.unit | power1: mana - absorbed * @mana_per_absorbed_damage}}
      {entity, damage - absorbed, %{aura | amount: amount - absorbed}}
    else
      {entity, damage, aura}
    end
  end

  defp absorb_with_aura(entity, damage, aura, _school_mask), do: {entity, damage, aura}

  defp exhausted_absorb?(%Holder{auras: auras}) do
    absorbs = Enum.filter(auras, fn %Aura{type: type} -> type in @absorb_auras end)
    absorbs != [] and Enum.all?(absorbs, fn %Aura{amount: amount} -> amount <= 0 end)
  end
end
