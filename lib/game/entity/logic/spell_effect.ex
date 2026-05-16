defmodule ThistleTea.Game.Entity.Logic.SpellEffect do
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  def receive(target, %CastContext{} = context, %Spell{} = spell, now) when is_integer(now) do
    context = %{context | target_guid: target.object.guid, spell: spell}
    apply_effects(target, context, spell.effects, [], now)
  end

  def receive(target, caster_guid, %Spell{} = spell, now) when is_integer(caster_guid) and is_integer(now) do
    receive(target, %CastContext{caster_guid: caster_guid, caster_level: 1}, spell, now)
  end

  def receive(target, _context, _spell, _now), do: {target, []}

  defp apply_effects(target, _context, [], events, _now), do: {target, events}

  defp apply_effects(target, context, effects, events, now) do
    if Core.dead?(target) do
      {target, events}
    else
      do_apply_effects(target, context, effects, events, now)
    end
  end

  defp do_apply_effects(target, context, [effect | rest], events, now) do
    {target, effect_events} = apply_effect(target, context, context.spell, effect, now)
    apply_effects(target, context, rest, events ++ effect_events, now)
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :school_damage} = effect, now) do
    apply_damage_effect(state, context, spell, effect, now)
  end

  defp apply_effect(
         state,
         %CastContext{} = context,
         spell,
         %Effect{type: :persistent_area_aura, aura: :periodic_damage} = effect,
         now
       ) do
    apply_damage_effect(state, context, spell, effect, now, periodic?: true)
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :apply_aura}, now) do
    Aura.apply_spell(state, context, spell, now)
  end

  defp apply_effect(
         state,
         %CastContext{} = context,
         _spell,
         %Effect{type: :trigger_spell, trigger_spell_id: spell_id},
         _now
       )
       when is_integer(spell_id) and spell_id > 0 do
    event = Event.trigger_spell(context.caster_guid, context.caster_level, state.object.guid, spell_id)
    {state, [event]}
  end

  defp apply_effect(state, _context, _spell, _effect, _now), do: {state, []}

  defp apply_damage_effect(state, %CastContext{} = context, spell, %Effect{} = effect, now, opts \\ [])
       when is_integer(now) do
    damage = Effect.damage_roll(effect)

    state = Core.take_damage(state, damage, now)
    event = Event.spell_damage(context.caster_guid, state.object.guid, spell, damage, opts)

    {state, [event]}
  end
end
