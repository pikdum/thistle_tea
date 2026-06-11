defmodule ThistleTea.Game.Entity.Logic.SpellEffect do
  @moduledoc """
  Applies a cast spell's effects (damage, healing, auras, item creation, …) to
  a target entity, returning the updated entity and the events to emit.
  """
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
    healing =
      Effect.damage_roll(effect) + bonus_amount(context.healing_bonus, spell) +
        Aura.flat_modifier(state, :mod_healing, Spell.school_mask(spell))

    {Core.heal(state, max(healing, 0)), []}
  end

  defp apply_effect(state, %CastContext{}, _spell, %Effect{type: :persistent_area_aura}, _now) do
    {state, []}
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

  defp apply_effect(
         %{movement_block: %{position: {x, y, z, o}}} = state,
         %CastContext{},
         _spell,
         %Effect{type: :leap} = effect,
         _now
       ) do
    distance = if is_number(effect.radius_yards) and effect.radius_yards > 0, do: effect.radius_yards, else: 20.0
    destination = {x + :math.cos(o) * distance, y + :math.sin(o) * distance, z, o}
    {state, [Event.leap(destination)]}
  end

  defp apply_effect(state, %CastContext{}, %Spell{id: spell_id}, %Effect{type: :teleport_units}, _now) do
    {state, [Event.teleport_to_spell_target(spell_id)]}
  end

  defp apply_effect(state, %CastContext{}, _spell, %Effect{type: :create_item, misc_value: item_id} = effect, _now)
       when is_integer(item_id) and item_id > 0 do
    count = max(Effect.damage_roll(effect), 1)
    {state, [Event.create_item(item_id, count)]}
  end

  defp apply_effect(state, %CastContext{}, _spell, %Effect{type: :interrupt_cast}, _now) do
    case state do
      %{internal: %{casting: casting} = internal, unit: unit} when not is_nil(casting) ->
        state = %{
          state
          | internal: %{internal | casting: nil},
            unit: %{unit | channel_spell: 0, channel_object: 0}
        }

        {Core.mark_broadcast_update(state), [Event.object_update(:values)]}

      _ ->
        {state, []}
    end
  end

  defp apply_effect(state, %CastContext{}, _spell, %Effect{type: :dispel, misc_value: dispel_type}, now) do
    Aura.dispel(state, dispel_type, now)
  end

  defp apply_effect(state, _context, _spell, _effect, _now), do: {state, []}

  defp apply_damage_effect(state, %CastContext{} = context, spell, %Effect{} = effect, now, opts \\ [])
       when is_integer(now) do
    damage =
      max(
        Effect.damage_roll(effect) + damage_bonus(context, spell, opts) +
          Aura.flat_modifier(state, :mod_damage_taken, Spell.school_mask(spell)),
        0
      )

    state = Core.take_damage(state, damage, now, school: school_atom(spell))
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
