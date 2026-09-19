defmodule ThistleTea.Game.Entity.Logic.ResistancePenetration do
  @moduledoc """
  Snapshots school-masked resistance modifiers from equipment and auras.
  Damage resolves them against the recipient's current armor or resistance,
  without changing that recipient's stats or reducing innate level resistance.
  """

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Spell

  def snapshot(%{unit: %Unit{} = unit}) do
    Map.get(unit.equipment_bonuses || %{}, :resistance_penetration, []) ++
      aura_amounts(unit.auras)
  end

  def snapshot(_entity), do: []

  defp aura_amounts(holders) when is_list(holders) do
    for %Holder{auras: auras, stacks: stacks} <- holders,
        %Aura{type: :mod_target_resistance, amount: amount, misc_value: mask} <- auras,
        is_integer(amount) and is_integer(mask),
        do: {mask, amount * max(stacks || 1, 1)}
  end

  defp aura_amounts(_holders), do: []

  def resistance(base, modifiers, school) do
    max((base || 0) + AuraLogic.versus_amount(modifiers, Spell.school_mask(school)), 0)
  end
end
