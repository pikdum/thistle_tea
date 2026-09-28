defmodule ThistleTea.Game.Entity.Logic.Engineering do
  @moduledoc "Scripted engineering outcomes expressed as ordinary spell requests."

  alias ThistleTea.Game.Entity.Data.Component.Internal.Guardian
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell.CastContext

  @guardian_passives %{2675 => 4051, 2678 => 23_051, 8615 => 23_050, 8937 => 13_260, 12_473 => 23_052}

  def guardian_passive(entry), do: Map.get(@guardian_passives, entry)

  def guardian_addon_auras(2675, spells), do: Enum.reject(spells, &(&1.id in [4051, 8327]))
  def guardian_addon_auras(entry, spells), do: Enum.reject(spells, &(&1.id == guardian_passive(entry)))

  def guardian_lifetime(2675, _duration, now),
    do: %Guardian{expires_at: now + 180_000, expiration_spell_id: 4050, corpse_delay_ms: 5_000}

  def guardian_lifetime(8937, _duration, now),
    do: %Guardian{expires_at: now + 60_000, expiration_spell_id: 13_259, corpse_delay_ms: 5_000}

  def guardian_lifetime(_entry, duration, now), do: %Guardian{expires_at: if(duration > 0, do: now + duration)}

  def goblin_bomb(entity, %CastContext{cast_item_guid: item_guid} = context)
      when is_integer(item_guid) and entity.object.guid == context.caster_guid do
    choices =
      Enum.map([{1, 13_261}, {9, 13_258}], fn {weight, spell_id} ->
        event =
          Effects.trigger_spell(context.caster_guid, context.caster_level, context.caster_guid, spell_id,
            cast_item_guid: if(spell_id == 13_258, do: item_guid),
            resolve_targets?: true
          )

        {weight, [event]}
      end)

    {entity, [%Effects.RandomChoice{choices: choices}]}
  end

  def goblin_bomb(entity, _context), do: {entity, []}

  def net_o_matic(target, %CastContext{} = context) do
    choices =
      Enum.map([{1, 16_566}, {1, 13_119}, {8, 13_099}], fn {weight, spell_id} ->
        trigger =
          Effects.trigger_spell(context.caster_guid, context.caster_level, target.object.guid, spell_id,
            resolve_targets?: true,
            hit_context: context
          )

        {weight, [trigger]}
      end)

    {target, [%Effects.RandomChoice{choices: choices}]}
  end

  def net_backfire(entity, %CastContext{} = context) do
    trigger =
      Effects.trigger_spell(context.caster_guid, context.caster_level, context.caster_guid, 13_138,
        target_role: :other,
        hit_context: context
      )

    {entity, [trigger]}
  end

  def universal_remote(target, %CastContext{} = context) do
    control = device_trigger(context.caster_guid, context.caster_level, target.object.guid, 8345)
    malfunction = device_trigger(context.caster_guid, context.caster_level, target.object.guid, 8346)
    enrage = device_trigger(target.object.guid, target.unit.level, target.object.guid, 8599)

    {target, [%Effects.RandomChoice{choices: [{1, [control]}, {1, [malfunction]}, {1, [enrage]}]}]}
  end

  def mind_control_cap(target, %CastContext{} = context) do
    control = device_trigger(context.caster_guid, context.caster_level, target.object.guid, 13_181)

    backfire =
      if context.caster_shapeshift_form in [nil, 0],
        do: [device_trigger(target.object.guid, target.unit.level, context.caster_guid, 13_181)],
        else: []

    {target, [%Effects.RandomChoice{choices: [{1, []}, {1, backfire}, {4, [control]}]}]}
  end

  defp device_trigger(source_guid, level, target_guid, spell_id) do
    Effects.trigger_spell(source_guid, level || 1, target_guid, spell_id, resolve_targets?: true)
  end
end
