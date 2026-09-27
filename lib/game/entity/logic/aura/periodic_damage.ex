defmodule ThistleTea.Game.Entity.Logic.Aura.PeriodicDamage do
  @moduledoc """
  Calculates periodic damage from its stored caster snapshot and executed tick
  count. Target bonuses apply before fractional rounding, resistance and absorption.
  """

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.DamageReceived
  alias ThistleTea.Game.Entity.Logic.Warlock
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  def amount(entity, %Holder{} = holder, %Aura{} = aura, roll \\ &:rand.uniform/0) do
    effect = Enum.find(holder.spell.effects, &(&1.index == aura.index))
    damage = base_amount(entity, holder, aura)
    damage = DamageReceived.spell_amount(entity, damage, holder.spell, effect, :dot, max(holder.stacks || 1, 1))
    Math.dither(damage, roll)
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
end
