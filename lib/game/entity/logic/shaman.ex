defmodule ThistleTea.Game.Entity.Logic.Shaman do
  @moduledoc """
  Pure Shaman weapon-imbue proc decisions. Enchantment and VMangos PPM data
  are supplied by the player boundary.
  """
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @flametongue_damage_spell 10_444

  def trigger_weapon_enchant(entity, payload, proc, ppm, roll \\ &:rand.uniform/0)

  def trigger_weapon_enchant(entity, %{outcome: outcome, victim_guid: victim_guid}, proc, ppm, roll)
      when outcome in [:normal, :crit] and is_map(proc) and is_number(ppm) and is_function(roll, 0) do
    chance = proc_chance(proc, ppm)

    if roll.() <= chance do
      trigger_proc(entity, victim_guid, proc)
    else
      entity
    end
  end

  def trigger_weapon_enchant(entity, _payload, _proc, _ppm, _roll), do: entity

  defp trigger_proc(entity, victim_guid, %{proc_spell: %Spell{} = spell} = proc) do
    if flametongue_proc?(spell) do
      trigger_flametongue(entity, victim_guid, spell, proc.attack_time_ms)
    else
      Event.enqueue(entity, Event.trigger_spell(entity.object.guid, entity.unit.level || 1, victim_guid, spell.id))
    end
  end

  defp trigger_proc(entity, victim_guid, proc) do
    Event.enqueue(
      entity,
      Event.trigger_spell(entity.object.guid, entity.unit.level || 1, victim_guid, proc.effect.spell_id)
    )
  end

  defp flametongue_proc?(%Spell{} = spell), do: Spell.vmangos_script?(spell, "spell_shaman_flametongue_proc_dummy")

  defp trigger_flametongue(entity, victim_guid, proc_spell, attack_time_ms) do
    with %Spell{} = damage_spell <- SpellLoader.load(@flametongue_damage_spell),
         %Effect{} = effect <- List.first(proc_spell.effects),
         %Effect{} = damage_effect <- List.first(damage_spell.effects) do
      context = CastContext.from_caster(entity, proc_spell, victim_guid)
      fire_bonus = Map.get(context.spell_damage_bonus, :fire, 0)
      damage = flametongue_damage(Effect.damage_roll(effect), fire_bonus, attack_time_ms)
      spell = %{damage_spell | effects: [%{damage_effect | base_points: damage, die_sides: 0}]}
      cast_context = %{CastContext.from_caster(entity, spell, victim_guid) | spell_damage_bonus: %{}}
      Event.enqueue(entity, Event.deliver_spell(victim_guid, cast_context, spell))
    else
      _ -> entity
    end
  end

  def flametongue_damage(base_damage, fire_bonus, attack_time_ms)
      when is_number(base_damage) and is_number(fire_bonus) and is_number(attack_time_ms) do
    round((base_damage + 3.85 * fire_bonus) * 0.01 * attack_time_ms / 1_000)
  end

  defp proc_chance(%{effect: %{amount: amount}}, _ppm) when is_integer(amount) and amount > 0,
    do: min(amount / 100, 1.0)

  defp proc_chance(%{attack_time_ms: attack_time_ms}, ppm) when is_number(attack_time_ms) and attack_time_ms > 0,
    do: min(ppm * attack_time_ms / 60_000, 1.0)

  defp proc_chance(_proc, _ppm), do: 0.0
end
