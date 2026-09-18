defmodule ThistleTea.Game.Entity.Logic.TargetSpellPower do
  @moduledoc """
  Combines school spell power with snapshotted creature-specific bonuses.
  Each recipient selects its matching creature masks before coefficient
  scaling; periodic effects retain the amount chosen at application.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.CreatureType
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext

  def snapshot(%{unit: %Unit{} = unit}) do
    Map.get(unit.equipment_bonuses || %{}, :spell_damage_versus, []) ++ aura_amounts(unit.auras)
  end

  def snapshot(_entity), do: []

  defp aura_amounts(holders) when is_list(holders) do
    for %Holder{auras: auras, stacks: stacks} <- holders,
        %Aura{type: :mod_flat_spell_damage_versus, amount: amount, misc_value: mask} <- auras,
        is_integer(amount) and is_integer(mask) do
      {mask, amount * max(stacks || 1, 1)}
    end
  end

  defp aura_amounts(_holders), do: []

  def benefit(target, %CastContext{} = context, %Spell{} = spell) do
    school = Enum.at([:physical, :holy, :fire, :nature, :frost, :shadow, :arcane], Spell.school_index(spell))

    Map.get(context.spell_damage_bonus, school, 0) +
      AuraLogic.versus_amount(context.spell_damage_versus, CreatureType.mask(target))
  end
end
