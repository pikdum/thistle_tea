defmodule ThistleTea.Game.Entity.Logic.SpellEffect do
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  def receive(target, %CastContext{} = context, %Spell{} = spell) do
    context = %{context | target_guid: target.object.guid, spell: spell}
    apply_effects(target, context, spell.effects, [])
  end

  def receive(target, caster_guid, %Spell{} = spell) when is_integer(caster_guid) do
    receive(target, %CastContext{caster_guid: caster_guid, caster_level: 1}, spell)
  end

  def receive(target, _context, _spell), do: {target, []}

  defp apply_effects(target, _context, [], events), do: {target, events}

  defp apply_effects(target, context, effects, events) do
    if Core.dead?(target) do
      {target, events}
    else
      do_apply_effects(target, context, effects, events)
    end
  end

  defp do_apply_effects(target, context, [effect | rest], events) do
    {target, effect_events} = apply_effect(target, context, context.spell, effect)
    apply_effects(target, context, rest, events ++ effect_events)
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :school_damage} = effect) do
    apply_damage_effect(state, context, spell, effect)
  end

  defp apply_effect(
         state,
         %CastContext{} = context,
         spell,
         %Effect{type: :persistent_area_aura, aura: :periodic_damage} = effect
       ) do
    apply_damage_effect(state, context, spell, effect, periodic?: true)
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :apply_aura}) do
    Aura.apply_spell(state, context, spell)
  end

  defp apply_effect(state, _context, _spell, _effect), do: {state, []}

  defp apply_damage_effect(state, %CastContext{} = context, spell, %Effect{} = effect, opts \\ []) do
    damage = Effect.damage_roll(effect)

    state = Core.take_damage(state, damage)
    event = Event.spell_damage(context.caster_guid, state.object.guid, spell, damage, opts)

    {state, [event]}
  end
end
