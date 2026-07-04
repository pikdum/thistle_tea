defmodule ThistleTea.Game.Entity.Logic.SpellEffect do
  @moduledoc """
  Applies a cast spell's effects (damage, healing, auras, item creation, …) to
  a target entity, returning the updated entity and the events to emit.
  """
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Scripts

  @schools [:physical, :holy, :fire, :nature, :frost, :shadow, :arcane]

  @resurrect_effects [:resurrect, :resurrect_new]

  def receive(target, %CastContext{} = context, %Spell{} = spell, now) when is_integer(now) do
    context = %{context | target_guid: target.object.guid, spell: spell}
    apply_effects(target, context, spell.effects, [], now)
  end

  def receive(target, caster_guid, %Spell{} = spell, now) when is_integer(caster_guid) and is_integer(now) do
    receive(target, %CastContext{caster_guid: caster_guid, caster_level: 1}, spell, now)
  end

  def receive(target, _context, _spell, _now), do: {target, []}

  defp apply_effects(target, context, effects, events, now) do
    apply_effects(target, context, effects, events, false, now)
  end

  defp apply_effects(target, _context, [], events, _aura_applied?, _now), do: {target, events}

  defp apply_effects(target, context, effects, events, aura_applied?, now) do
    effects =
      if Core.dead?(target) do
        Enum.filter(effects, &match?(%Effect{type: type} when type in @resurrect_effects, &1))
      else
        effects
      end

    do_apply_effects(target, context, effects, events, aura_applied?, now)
  end

  defp do_apply_effects(target, _context, [], events, _aura_applied?, _now), do: {target, events}

  defp do_apply_effects(target, context, [effect | rest], events, aura_applied?, now) do
    {target, events, aura_applied?} = apply_one_effect(target, context, effect, events, aura_applied?, now)
    apply_effects(target, context, rest, events, aura_applied?, now)
  end

  defp apply_one_effect(target, context, effect, events, aura_applied?, now) do
    cond do
      channel_ticked_trigger?(context.spell, effect) ->
        event =
          Event.trigger_spell(context.caster_guid, context.caster_level, target.object.guid, effect.trigger_spell_id)

        {target, events ++ [event], aura_applied?}

      match?(%Effect{type: :apply_aura}, effect) and aura_applied? ->
        {target, events, aura_applied?}

      match?(%Effect{type: :apply_aura}, effect) ->
        {target, aura_events} = apply_auras(target, context, now)
        {target, events ++ aura_events, true}

      true ->
        {target, effect_events} = apply_effect(target, context, context.spell, effect, now)
        {target, events ++ effect_events, aura_applied?}
    end
  end

  defp apply_auras(target, context, now) do
    {target, events} = Aura.apply_spell(target, context, context.spell, now)
    {target, events ++ script_trigger_events(target, context)}
  end

  defp script_trigger_events(target, %CastContext{spell: spell} = context) do
    with trigger_id when is_integer(trigger_id) <- Scripts.apply_trigger(spell),
         true <- Aura.has_spell?(target, spell.id) do
      [Event.trigger_spell(context.caster_guid, context.caster_level, target.object.guid, trigger_id)]
    else
      _ -> []
    end
  end

  defp channel_ticked_trigger?(spell, %Effect{type: :apply_aura, aura: :periodic_trigger_spell, trigger_spell_id: id})
       when is_integer(id) and id > 0 do
    Spell.attribute?(spell, :channeled)
  end

  defp channel_ticked_trigger?(_spell, _effect), do: false

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :school_damage} = effect, now) do
    apply_damage_effect(state, context, spell, effect, now)
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :heal} = effect, _now) do
    healing =
      Effect.damage_roll(effect) + bonus_amount(context.healing_bonus, spell) +
        Aura.flat_modifier(state, :mod_healing, Spell.school_mask(spell))

    healing = trunc(healing * healing_taken_multiplier(state, spell))

    {Core.heal(state, max(healing, 0)), []}
  end

  defp apply_effect(state, %CastContext{}, _spell, %Effect{type: :persistent_area_aura}, _now) do
    {state, []}
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

  defp apply_effect(state, %CastContext{} = context, _spell, %Effect{type: :dispel, misc_value: dispel_type}, now) do
    Aura.dispel(state, dispel_type, now, dispel_polarity(context))
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :power_burn} = effect, now) do
    drained = min(Effect.damage_roll(effect), max(state.unit.power1 || 0, 0))

    if drained > 0 do
      state =
        %{state | unit: %{state.unit | power1: state.unit.power1 - drained}}
        |> Core.mark_broadcast_update()

      damage = trunc(drained * burn_multiplier(effect))
      state = Core.take_damage(state, damage, now, school: school_atom(spell), source: context.caster_guid)
      event = Event.spell_damage(context.caster_guid, state.object.guid, spell, damage)

      {state, [event]}
    else
      {state, []}
    end
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :resurrect_new} = effect, _now) do
    if resurrectable?(state) do
      health = max(Effect.damage_roll(effect), 1)
      mana = max(effect.misc_value || 0, 0)
      offer_resurrect(state, context, spell, health, mana)
    else
      {state, []}
    end
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :resurrect} = effect, _now) do
    if resurrectable?(state) do
      percent = max(Effect.damage_roll(effect), 0) / 100
      health = max(trunc((state.unit.max_health || 1) * percent), 1)
      mana = max(trunc((state.unit.max_power1 || 0) * percent), 0)
      offer_resurrect(state, context, spell, health, mana)
    else
      {state, []}
    end
  end

  defp apply_effect(state, _context, _spell, _effect, _now), do: {state, []}

  defp resurrectable?(%{player: _player} = state) do
    Core.dead?(state) or Death.ghost?(state)
  end

  defp resurrectable?(_state), do: false

  defp offer_resurrect(%{internal: internal} = state, %CastContext{} = context, spell, health, mana) do
    pending = %{
      caster_guid: context.caster_guid,
      position: context.caster_position,
      health: health,
      mana: mana
    }

    state = %{state | internal: %{internal | pending_resurrect: pending}}
    {state, [Event.resurrect_request(context.caster_guid, spell.id, health, mana)]}
  end

  defp burn_multiplier(%Effect{multiple_value: multiple}) when is_number(multiple) and multiple > 0, do: multiple
  defp burn_multiplier(_effect), do: 1.0

  defp dispel_polarity(%CastContext{target_hostile?: true}), do: :positive
  defp dispel_polarity(%CastContext{target_hostile?: false}), do: :negative
  defp dispel_polarity(_context), do: nil

  defp healing_taken_multiplier(state, spell) do
    percent = Aura.flat_modifier(state, :mod_healing_pct, Spell.school_mask(spell))
    max(100 + percent, 0) / 100
  end

  defp apply_damage_effect(state, %CastContext{} = context, spell, %Effect{} = effect, now, opts \\ [])
       when is_integer(now) do
    damage =
      max(
        Effect.damage_roll(effect) + damage_bonus(context, spell, opts) +
          Aura.flat_modifier(state, :mod_damage_taken, Spell.school_mask(spell)),
        0
      )

    school = school_atom(spell)
    resisted = school_resisted_amount(state, damage, school, context.caster_level, opts)
    damage = damage - resisted

    {state, absorbed} = Core.take_damage_with_absorb(state, damage, now, school: school, source: context.caster_guid)

    event =
      Event.spell_damage(
        context.caster_guid,
        state.object.guid,
        spell,
        damage,
        opts ++ [resisted: resisted, absorbed: absorbed]
      )

    {state, [event]}
  end

  defp school_resisted_amount(_state, damage, _school, _caster_level, _opts) when damage <= 0, do: 0
  defp school_resisted_amount(_state, _damage, :physical, _caster_level, _opts), do: 0

  defp school_resisted_amount(%{unit: unit} = state, damage, school, caster_level, opts) do
    caster_level = if is_integer(caster_level) and caster_level > 0, do: caster_level, else: 1
    resistance = Map.get(unit, :"#{school}_resistance") || 0
    target_creature? = not is_map(Map.get(state, :player))
    level_diff = (unit.level || 1) - caster_level

    SpellResist.resisted_amount(damage, resistance, caster_level,
      target_creature?: target_creature?,
      level_diff: level_diff,
      dot?: Keyword.get(opts, :periodic?, false)
    )
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
