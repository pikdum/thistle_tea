defmodule ThistleTea.Game.Core.Aura.ProcChance do
  @moduledoc "Resolves aura proc chances from current attack periods and the bearer or owner's spell modifiers."

  alias ThistleTea.Game.Core.Aura.ProcEquipment
  alias ThistleTea.Game.Core.Rolls
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Modifiers
  alias ThistleTea.Game.Core.Spell.Proc
  alias ThistleTea.Game.Core.Stats.AttackSpeed

  def roll?(entity, spell, direction, context, roll \\ Rolls.system()) do
    chance = chance(entity, spell, direction, context)
    chance >= 100 or (chance > 0 and value(roll) * 100 <= chance)
  end

  defp value(%Rolls{} = rolls), do: Rolls.uniform(rolls, :aura_proc)
  defp value(roll) when is_function(roll, 0), do: roll.()

  def chance(entity, %Spell{} = spell, direction, context) do
    chance = Proc.chance(spell, attack_time(entity, direction, context))
    Modifiers.value(entity, spell, :chance_of_success, chance)
  end

  defp attack_time(%{unit: unit}, :outgoing, context), do: AttackSpeed.base_ms(unit, ProcEquipment.attack_hand(context))
  defp attack_time(_entity, :incoming, _context), do: nil
end
