defmodule ThistleTea.Game.Entity.Logic.Shaman do
  @moduledoc """
  Weapon enchantment proc decisions, including Shaman imbue effects.
  Enchantment and VMangos PPM data are supplied by the player boundary.
  """
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.ExtraAttacks
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.ProcOrigin
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @flametongue_damage_spell 10_444

  def trigger_weapon_enchant(entity, payload, proc, ppm, roll \\ &:rand.uniform/0)

  def trigger_weapon_enchant(entity, payload, proc, ppm, roll) do
    {entity, _triggered?} = resolve_weapon_enchant(entity, payload, proc, ppm, roll)
    entity
  end

  def resolve_weapon_enchant(entity, payload, proc, ppm, roll \\ &:rand.uniform/0)

  def resolve_weapon_enchant(entity, %{outcome: outcome, victim_guid: victim_guid} = payload, proc, ppm, roll)
      when outcome in [:normal, :crit, :glancing, :crushing, :block] and is_map(proc) and is_number(ppm) and
             is_function(roll, 0) do
    chance = modified_proc_chance(entity, proc, ppm)

    extra_attack? = Map.get(payload, :extra_attack?, false)

    if not (extra_attack? and ExtraAttacks.spell?(Map.get(proc, :proc_spell))) and chance > 0 and roll.() <= chance do
      {trigger_proc(entity, victim_guid, proc, extra_attack?), true}
    else
      {entity, false}
    end
  end

  def resolve_weapon_enchant(entity, _payload, _proc, _ppm, _roll), do: {entity, false}

  defp modified_proc_chance(entity, %{proc_spell: %Spell{} = spell} = proc, ppm) do
    (Modifiers.value(entity, spell, :chance_of_success, proc_chance(proc, ppm) * 100) / 100)
    |> max(0.0)
    |> min(1.0)
  end

  defp modified_proc_chance(_entity, proc, ppm), do: proc_chance(proc, ppm)

  defp trigger_proc(entity, victim_guid, %{proc_spell: %Spell{} = spell} = proc, extra_attack?) do
    if flametongue_proc?(spell) do
      trigger_flametongue(entity, victim_guid, spell, proc)
    else
      target_guid = if Spell.harmful?(spell), do: victim_guid, else: entity.object.guid

      Effects.enqueue(
        entity,
        Effects.trigger_spell(entity.object.guid, entity.unit.level || 1, target_guid, spell.id,
          cast_item_guid: Map.get(proc, :item_guid),
          extra_attack?: extra_attack?
        )
      )
    end
  end

  defp trigger_proc(entity, victim_guid, proc, extra_attack?) do
    Effects.enqueue(
      entity,
      Effects.trigger_spell(entity.object.guid, entity.unit.level || 1, victim_guid, proc.effect.spell_id,
        cast_item_guid: Map.get(proc, :item_guid),
        extra_attack?: extra_attack?
      )
    )
  end

  defp flametongue_proc?(%Spell{} = spell), do: Spell.vmangos_script?(spell, "spell_shaman_flametongue_proc_dummy")

  defp trigger_flametongue(entity, victim_guid, proc_spell, proc) do
    with %Spell{} = damage_spell <- SpellLoader.load(@flametongue_damage_spell),
         %Effect{} = effect <- List.first(proc_spell.effects),
         %Effect{} = damage_effect <- List.first(damage_spell.effects) do
      context = CastContext.from_caster(entity, proc_spell, victim_guid)
      fire_bonus = Map.get(context.spell_damage_bonus, :fire, 0)
      damage = flametongue_damage(Effect.damage_roll(effect), fire_bonus, proc.attack_time_ms)
      spell = %{damage_spell | effects: [%{damage_effect | base_points: damage, die_sides: 0}]}

      cast_context = %{
        CastContext.from_caster(entity, spell, victim_guid)
        | spell_damage_bonus: %{},
          triggered?: true,
          cast_item_guid: Map.get(proc, :item_guid)
      }

      completion = %Effects.SpellCastCompleted{
        source_guid: entity.object.guid,
        target_guid: victim_guid,
        spell: spell,
        proc_origin: ProcOrigin.classify(spell, cast_context)
      }

      Effects.enqueue(entity, [Effects.deliver_spell(victim_guid, cast_context, spell), completion])
    else
      _ -> entity
    end
  end

  def flametongue_damage(base_damage, fire_bonus, attack_time_ms)
      when is_number(base_damage) and is_number(fire_bonus) and is_number(attack_time_ms) do
    round((base_damage + 3.85 * fire_bonus) * 0.01 * attack_time_ms / 1_000)
  end

  defp proc_chance(%{attack_time_ms: attack_time_ms}, ppm)
       when is_number(attack_time_ms) and attack_time_ms > 0 and is_number(ppm) and ppm > 0,
       do: min(ppm * attack_time_ms / 60_000, 1.0)

  defp proc_chance(%{effect: %{amount: amount}}, _ppm) when is_integer(amount) and amount > 0,
    do: min(amount / 100, 1.0)

  defp proc_chance(%{attack_time_ms: attack_time_ms}, ppm) when is_number(attack_time_ms) and attack_time_ms > 0,
    do: min(if(ppm > 0, do: ppm, else: 1.0) * attack_time_ms / 60_000, 1.0)

  defp proc_chance(_proc, _ppm), do: 0.0
end
