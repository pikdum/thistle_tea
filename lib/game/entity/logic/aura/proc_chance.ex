defmodule ThistleTea.Game.Entity.Logic.Aura.ProcChance do
  @moduledoc "Resolves aura proc chances from current attack periods and the bearer or owner's spell modifiers."

  alias ThistleTea.Game.Entity.Logic.AttackSpeed
  alias ThistleTea.Game.Entity.Logic.Aura.ProcEquipment
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Proc

  def roll?(entity, spell, direction, context, roll \\ &:rand.uniform/0) do
    chance = chance(entity, spell, direction, context)
    chance >= 100 or (chance > 0 and roll.() * 100 <= chance)
  end

  def chance(entity, %Spell{} = spell, direction, context) do
    chance = Proc.chance(spell, attack_time(entity, direction, context))
    Modifiers.value(entity, spell, :chance_of_success, chance)
  end

  defp attack_time(%{unit: unit}, :outgoing, context), do: AttackSpeed.base_ms(unit, ProcEquipment.attack_hand(context))
  defp attack_time(_entity, :incoming, _context), do: nil
end
