defmodule ThistleTea.Game.Entity.Logic.Aura.PeriodicDamage do
  @moduledoc """
  Calculates periodic damage from its stored caster snapshot and executed tick
  count. Target bonuses apply before fractional rounding, resistance and absorption.
  """

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AttackDamageTaken
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Warlock
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Coefficient
  alias ThistleTea.Game.Spell.Effect

  def amount(entity, %Holder{} = holder, %Aura{} = aura, roll \\ &:rand.uniform/0) do
    effect = Enum.find(holder.spell.effects, &(&1.index == aura.index))
    damage = base_amount(entity, holder, aura)
    damage = received_amount(entity, holder, effect, damage)
    rounded_amount(damage, roll)
  end

  defp base_amount(%{unit: %Unit{max_health: health}}, %Holder{stacks: stacks}, %Aura{
         type: :periodic_damage_percent,
         amount: amount
       }) do
    div(max(health || 0, 0) * max(amount || 0, 0) * max(stacks || 1, 1), 100)
  end

  defp base_amount(_entity, %Holder{spell: %Spell{id: 12_654}}, %Aura{amount: amount}), do: amount

  defp base_amount(_entity, %Holder{spell: spell, stacks: stacks}, %Aura{amount: amount} = aura) do
    max(amount, 0) * max(stacks || 1, 1) + ramp_offset(spell, aura)
  end

  defp ramp_offset(%Spell{} = spell, %Aura{type: :periodic_damage, tick_count: tick}) when tick > 0 do
    case Enum.find(spell.effects, &(&1.index == 0)) do
      %Effect{} = effect ->
        base = (effect.base_points || 0) + (effect.base_dice || 0)

        cond do
          Warlock.curse_of_agony?(spell) -> (div(tick - 1, 4) - 1) * base / 2
          Spell.family_flag?(spell, 6, 0x00200000) -> (div(tick - 1, 2) - 1) * base / 3
          true -> 0
        end

      nil ->
        0
    end
  end

  defp ramp_offset(_spell, _aura), do: 0

  defp received_amount(entity, %Holder{spell: spell, stacks: stacks}, effect, damage) do
    stacks = max(stacks || 1, 1)

    damage =
      if spell.dmg_class in [2, 3] do
        AttackDamageTaken.spell_amount(entity, damage, spell, effect, :dot, stacks)
      else
        flat = AuraLogic.flat_modifier(entity, :mod_damage_taken, Spell.school_mask(spell))
        damage + max(flat * coefficient(spell, effect) * stacks, -damage / 2)
      end

    max(damage * AuraLogic.percent_multiplier(entity, :mod_damage_percent_taken, Spell.school_mask(spell)), 0)
  end

  defp coefficient(%Spell{} = spell, %Effect{} = effect) do
    if Spell.custom?(spell, :fixed_damage), do: 0, else: Coefficient.value(spell, effect, :dot)
  end

  defp coefficient(_spell, nil), do: 0

  defp rounded_amount(damage, roll) do
    whole = trunc(damage)
    if damage > whole and roll.() < damage - whole, do: whole + 1, else: whole
  end
end
