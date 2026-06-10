defmodule ThistleTea.Game.Entity.Logic.SpellEffect do
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  @schools [:physical, :holy, :fire, :nature, :frost, :shadow, :arcane]

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

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :heal} = effect, _now) do
    healing = Effect.damage_roll(effect) + bonus_amount(context.healing_bonus, spell)
    {Core.heal(state, healing), []}
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

  defp apply_effect(
         state,
         %CastContext{} = context,
         _spell,
         %Effect{type: :apply_aura, aura: :periodic_trigger_spell, trigger_spell_id: spell_id},
         _now
       )
       when is_integer(spell_id) and spell_id > 0 do
    event = Event.trigger_spell(context.caster_guid, context.caster_level, state.object.guid, spell_id)
    {state, [event]}
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
    damage = Effect.damage_roll(effect) + damage_bonus(context, spell, opts)

    state = Core.take_damage(state, damage, now)
    event = Event.spell_damage(context.caster_guid, state.object.guid, spell, damage, opts)

    {state, [event]}
  end

  defp damage_bonus(%CastContext{} = context, %Spell{} = spell, opts) do
    if Keyword.get(opts, :periodic?, false) do
      0
    else
      school_bonus = Map.get(context.spell_damage_bonus, school_atom(spell), 0)
      bonus_amount(school_bonus, spell)
    end
  end

  defp bonus_amount(bonus, %Spell{} = spell) when is_integer(bonus) and bonus > 0 do
    trunc(bonus * coefficient(spell))
  end

  defp bonus_amount(_bonus, _spell), do: 0

  defp coefficient(%Spell{cast_time_ms: cast_time_ms}) do
    cast_time_ms = if is_integer(cast_time_ms), do: cast_time_ms, else: 0
    min(max(cast_time_ms, 1500), 7000) / 3500
  end

  defp school_atom(%Spell{school: school}) when is_atom(school), do: school
  defp school_atom(%Spell{} = spell), do: Enum.at(@schools, Spell.school_index(spell), :physical)
end
