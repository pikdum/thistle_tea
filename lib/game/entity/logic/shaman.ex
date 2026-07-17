defmodule ThistleTea.Game.Entity.Logic.Shaman do
  @moduledoc """
  Pure Shaman weapon-imbue proc decisions. Enchantment and VMangos PPM data
  are supplied by the player boundary.
  """
  alias ThistleTea.Game.Entity.Logic.Event

  def trigger_weapon_enchant(entity, payload, proc, ppm, roll \\ &:rand.uniform/0)

  def trigger_weapon_enchant(entity, %{outcome: outcome, victim_guid: victim_guid}, proc, ppm, roll)
      when outcome in [:normal, :crit] and is_map(proc) and is_number(ppm) and is_function(roll, 0) do
    chance = proc_chance(proc, ppm)

    if roll.() <= chance do
      Event.enqueue(
        entity,
        Event.trigger_spell(entity.object.guid, entity.unit.level || 1, victim_guid, proc.effect.spell_id)
      )
    else
      entity
    end
  end

  def trigger_weapon_enchant(entity, _payload, _proc, _ppm, _roll), do: entity

  defp proc_chance(%{effect: %{amount: amount}}, _ppm) when is_integer(amount) and amount > 0,
    do: min(amount / 100, 1.0)

  defp proc_chance(%{attack_time_ms: attack_time_ms}, ppm) when is_number(attack_time_ms) and attack_time_ms > 0,
    do: min(ppm * attack_time_ms / 60_000, 1.0)

  defp proc_chance(_proc, _ppm), do: 0.0
end
