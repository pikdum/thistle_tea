defmodule ThistleTea.Game.Entity.Logic.WeaponProcs do
  @moduledoc "Weapon-hit qualification and innate item proc rolls over supplied equipment and spell data."

  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.ExtraAttacks
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Cooldowns

  def swing_events(target, attack, result, absorbed) do
    if result.outcome in [:normal, :crit, :glancing, :crushing, :block] and
         (result.damage > absorbed or result.outcome == :block) do
      hand =
        cond do
          Map.get(attack, :ranged?, false) -> :ranged
          Map.get(attack, :offhand?, false) -> :offhand
          true -> :mainhand
        end

      hit_events(target, Map.get(attack, :caster), hand, Map.get(attack, :extra_attack?, false))
    else
      []
    end
  end

  def spell_events(target, %CastContext{} = context, %Spell{} = spell) do
    if not context.proc_damage? and spell_allowed?(spell) do
      hand = if spell.equipped_item_class == 2 and Spell.ranged_attack?(spell), do: :ranged, else: :mainhand
      hit_events(target, context.caster_guid, hand, context.extra_attack?)
    else
      []
    end
  end

  def spell_allowed?(%Spell{equipped_item_class: 2, melee_range?: true}), do: true
  def spell_allowed?(%Spell{} = spell), do: Spell.custom?(spell, :trigger_weapon_procs)

  defp hit_events(%{object: %{guid: target}, unit: %{health: health}}, source, hand, extra_attack?)
       when is_integer(source) and source != target and is_integer(health) and health > 0 do
    if Guid.entity_type(source) == :player do
      [%Effects.TriggerWeaponProcs{source_guid: source, target_guid: target, hand: hand, extra_attack?: extra_attack?}]
    else
      []
    end
  end

  defp hit_events(_target, _source, _hand, _extra_attack?), do: []

  def spells(%ItemTemplate{} = item) do
    [
      {item.spellid_1, item.spelltrigger_1, item.spellppm_rate_1},
      {item.spellid_2, item.spelltrigger_2, item.spellppm_rate_2},
      {item.spellid_3, item.spelltrigger_3, item.spellppm_rate_3},
      {item.spellid_4, item.spelltrigger_4, item.spellppm_rate_4},
      {item.spellid_5, item.spelltrigger_5, item.spellppm_rate_5}
    ]
    |> Enum.flat_map(fn
      {id, 2, ppm} when is_integer(id) and id > 0 -> [{id, ppm}]
      _ -> []
    end)
  end

  def innate_events(character, %Effects.TriggerWeaponProcs{} = hit, %Item{} = item, spells, now, roll) do
    template = Item.template(item)
    extra_attack? = hit.extra_attack? or ExtraAttacks.pending?(character)

    {events, continue?, _extra_attack?} =
      template
      |> spells()
      |> Enum.reduce_while({[], true, extra_attack?}, fn {id, ppm}, {events, true, extra_attack?} ->
        spell = Map.get(spells, id)

        case proc_decision(character, spell, {ppm, template.delay}, now, roll, extra_attack?) do
          :stop ->
            {:halt, {events, false, extra_attack?}}

          :trigger ->
            event = trigger(character, hit, item, spell)
            {:cont, {events ++ [event], true, extra_attack? or ExtraAttacks.spell?(spell)}}

          :skip ->
            {:cont, {events, true, extra_attack?}}
        end
      end)

    {events, continue?}
  end

  defp proc_decision(character, %Spell{} = spell, {ppm, speed}, now, roll, extra_attack?) do
    cond do
      extra_attack? and ExtraAttacks.spell?(spell) -> :stop
      Cooldowns.on_gcd?(character, spell, now) -> :skip
      roll?(spell, ppm, speed, roll) -> :trigger
      true -> :skip
    end
  end

  defp proc_decision(_character, _spell, _rate, _now, _roll, _extra_attack?), do: :skip

  defp trigger(character, hit, item, spell) do
    Effects.trigger_spell(character.object.guid, character.unit.level || 1, hit.target_guid, spell.id,
      cast_item_guid: item.object.guid,
      attack_hand: hit.hand,
      extra_attack?: hit.extra_attack?,
      resolve_targets?: true,
      requires_living_target?: true
    )
  end

  defp roll?(spell, ppm, speed, roll) do
    chance = chance(spell, ppm, speed)
    chance >= 100 or (chance > 0 and roll.() * 100 <= chance)
  end

  def chance(%Spell{} = spell, ppm, speed) do
    cond do
      is_number(ppm) and ppm > 0 -> ppm_chance(ppm, speed)
      is_number(spell.proc_chance) and spell.proc_chance > 100 -> ppm_chance(1.0, speed)
      is_number(spell.proc_chance) -> max(spell.proc_chance, 0)
      true -> 0
    end
  end

  defp ppm_chance(ppm, speed) when is_number(speed) and speed > 0, do: min(ppm * speed / 600, 100.0)
  defp ppm_chance(_ppm, _speed), do: 0
end
