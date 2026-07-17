defmodule ThistleTea.Game.Entity.Logic.Warrior do
  @moduledoc """
  Warrior spell behavior that VMangos marks as scripted because DBC effects
  do not carry the required runtime combat values.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  def shield_slam_bonus(%Spell{} = spell, %Effect{index: 1}, block_value) do
    if Spell.vmangos_script?(spell, "spell_warrior_shield_slam"), do: max(block_value || 0, 0), else: 0
  end

  def shield_slam_bonus(_spell, _effect, _block_value), do: 0

  def filter_target_effects(effects, target_guid, %CastContext{selected_target_guid: target_guid}, %Spell{} = spell) do
    if Spell.vmangos_script?(spell, "spell_warrior_intimidating_shout") do
      Enum.filter(effects, &(&1.index == 0))
    else
      effects
    end
  end

  def filter_target_effects(effects, _target_guid, _context, _spell), do: effects

  def after_energize(%Character{} = character, %Spell{} = spell, now) do
    if Spell.vmangos_script?(spell, "spell_warrior_bloodrage") do
      PlayerCombat.mark_initiated(character, now)
    else
      character
    end
  end

  def after_energize(entity, _spell, _now), do: entity
end
