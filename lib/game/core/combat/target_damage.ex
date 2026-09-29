defmodule ThistleTea.Game.Core.Combat.TargetDamage do
  @moduledoc """
  Snapshots flat creature-specific damage from equipment and active auras.
  Weapon attacks add it after weapon scaling; magic adds it independently
  of spell power, while non-weapon melee and ranged effects use coefficients.
  """

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Creature.CreatureType
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Coefficient
  alias ThistleTea.Game.Core.Spell.Effect

  def snapshot(%{unit: %Unit{} = unit}) do
    Map.get(unit.equipment_bonuses || %{}, :damage_done_creature, []) ++ aura_amounts(unit.auras)
  end

  def snapshot(_entity), do: []

  def bonus(target, snapshot), do: Aura.versus_amount(snapshot, CreatureType.mask(target))

  def weapon_bonus(target, snapshot, %Spell{} = spell) do
    if ignores_bonus?(spell), do: 0, else: bonus(target, snapshot)
  end

  def spell_bonus(target, snapshot, %Spell{} = spell, %Effect{} = effect, damage_type) do
    cond do
      ignores_bonus?(spell) ->
        0

      spell.dmg_class in [2, 3] ->
        Coefficient.bonus(bonus(target, snapshot), spell, effect, damage_type)

      true ->
        bonus(target, snapshot)
    end
  end

  defp ignores_bonus?(spell) do
    Spell.custom?(spell, :fixed_damage) or Spell.attribute?(spell, :ignore_caster_modifiers) or spell.id == 12_654
  end

  defp aura_amounts(holders) when is_list(holders) do
    for %Holder{auras: auras, stacks: stacks} <- holders,
        %Aura{type: :mod_damage_done_creature, amount: amount, misc_value: mask} <- auras,
        is_integer(amount) and is_integer(mask) do
      {mask, amount * max(stacks || 1, 1)}
    end
  end

  defp aura_amounts(_holders), do: []
end
