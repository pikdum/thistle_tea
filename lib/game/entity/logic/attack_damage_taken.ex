defmodule ThistleTea.Game.Entity.Logic.AttackDamageTaken do
  @moduledoc """
  Applies melee and ranged damage-received auras before armor and attack
  outcomes. Flat bonuses scale with the receiving spell effect's coefficient
  for non-weapon damage; percentages multiply independently per holder.
  """

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Coefficient
  alias ThistleTea.Game.Spell.Effect

  def amount(entity, damage, kind, coefficient \\ 1.0)

  def amount(entity, damage, kind, coefficient) when damage > 0 and kind in [:melee, :ranged] do
    {flat_type, percent_type} = types(kind)
    flat = Aura.flat_amount(entity, flat_type) * coefficient
    max(trunc((damage + flat) * multiplier(entity, percent_type)), 0)
  end

  def amount(_entity, damage, _kind, _coefficient), do: max(damage, 0)

  def spell_amount(entity, damage, spell, effect \\ nil, damage_type \\ :direct, stacks \\ 1)

  def spell_amount(entity, damage, %Spell{dmg_class: class} = spell, effect, damage_type, stacks)
      when class in [2, 3] do
    kind = if class == 3, do: :ranged, else: :melee
    amount(entity, damage, kind, coefficient(spell, effect, damage_type) * max(stacks, 1))
  end

  def spell_amount(_entity, damage, _spell, _effect, _damage_type, _stacks), do: damage

  defp coefficient(%Spell{} = spell, %Effect{} = effect, damage_type) do
    if Spell.custom?(spell, :fixed_damage), do: 0.0, else: Coefficient.value(spell, effect, damage_type)
  end

  defp coefficient(_spell, nil, _damage_type), do: 1.0

  defp types(:melee), do: {:mod_melee_damage_taken, :mod_melee_damage_taken_pct}
  defp types(:ranged), do: {:mod_ranged_damage_taken, :mod_ranged_damage_taken_pct}

  defp multiplier(%{unit: %Unit{auras: holders}}, type) when is_list(holders) do
    for %Holder{auras: auras, stacks: stacks} <- holders,
        %AuraData{type: ^type, amount: amount} <- auras,
        is_number(amount),
        reduce: 1.0 do
      value -> value * max(100 + amount * max(stacks || 1, 1), 0) / 100
    end
  end

  defp multiplier(_entity, _type), do: 1.0
end
