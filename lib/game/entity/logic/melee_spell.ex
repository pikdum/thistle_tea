defmodule ThistleTea.Game.Entity.Logic.MeleeSpell do
  @moduledoc """
  On-next-swing melee spells (e.g. Heroic Strike): queueing the spell on the
  entity, consuming it when the swing lands, and folding its bonus damage into
  the attack.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  def queue_next_swing(%{internal: %Internal{} = internal} = entity, %Spell{} = spell) do
    %{entity | internal: %{internal | next_swing_spell: spell}}
  end

  def queue_next_swing(entity, _spell), do: entity

  def consume_next_swing(%{internal: %Internal{next_swing_spell: %Spell{} = spell} = internal} = entity) do
    {%{entity | internal: %{internal | next_swing_spell: nil}}, spell}
  end

  def consume_next_swing(entity), do: {entity, nil}

  def apply_to_attack(attack, %Spell{} = spell) when is_map(attack) do
    damage_bonus = damage_bonus(spell)

    attack
    |> Map.update(:min_damage, damage_bonus, &(&1 + damage_bonus))
    |> Map.update(:max_damage, damage_bonus, &(&1 + damage_bonus))
    |> Map.put(:spell_id, spell.id)
    |> Map.put(:queued_spell_id, spell.id)
    |> Map.put(:spell_school_mask, Spell.school_mask(spell))
  end

  def apply_to_attack(attack, _spell), do: attack

  defp damage_bonus(%Spell{} = spell) do
    spell
    |> Spell.damage_effects()
    |> Enum.filter(&(&1.type in [:weapon_damage, :weapon_damage_noschool]))
    |> Enum.map(&Effect.damage_roll/1)
    |> Enum.sum()
  end
end
