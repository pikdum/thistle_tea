defmodule ThistleTea.Game.Entity.Logic.SpellEffect.Script do
  @moduledoc false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Druid
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Hunter
  alias ThistleTea.Game.Entity.Logic.Mage
  alias ThistleTea.Game.Entity.Logic.PetTraining
  alias ThistleTea.Game.Entity.Logic.Racial
  alias ThistleTea.Game.Entity.Logic.Rogue
  alias ThistleTea.Game.Entity.Logic.Shapeshift
  alias ThistleTea.Game.Entity.Logic.Silithyst
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Amount
  alias ThistleTea.Game.Entity.Logic.SpellEffect.DamageHeal
  alias ThistleTea.Game.Entity.Logic.SpellTeaching
  alias ThistleTea.Game.Entity.Logic.Warlock
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Scripts
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.World.Loader.SpellPetAura, as: SpellPetAuraLoader

  def apply(%Character{} = state, %CastContext{} = context, spell, %Effect{type: type} = effect, _now)
      when type in [:learn_spell, :learn_pet_spell, :skill_step] do
    pet_guid = Companion.summon_guid(state)

    cond do
      PetTraining.training_effect?(effect) and context.caster_guid == state.object.guid and is_integer(pet_guid) ->
        {state, [%Effects.LearnPetSpell{target_guid: pet_guid, spell: spell}]}

      SpellTeaching.effect?(effect) and effect == Enum.find(spell.effects, &SpellTeaching.effect?/1) ->
        event = %Effects.TeachSpell{
          spell: spell,
          skill_steps: SpellTeaching.skill_steps(spell),
          cast_item_guid: if(context.caster_guid == state.object.guid, do: context.cast_item_guid)
        }

        {state, [event]}

      true ->
        {state, []}
    end
  end

  def apply(state, %CastContext{} = context, _spell, %Effect{type: :quest_complete, misc_value: quest_id}, _now)
      when is_integer(quest_id) and quest_id > 0 do
    {state, [Effects.quest_event_credit(context.caster_guid, quest_id)]}
  end

  def apply(
        state,
        %CastContext{} = context,
        spell,
        %Effect{type: :trigger_spell, trigger_spell_id: spell_id} = effect,
        _now
      )
      when is_integer(spell_id) and spell_id > 0 do
    if Semantics.rules(spell).dummy == :execute do
      {state, []}
    else
      target_guid = trigger_target_guid(state, context, effect)

      event =
        Effects.trigger_spell(context.caster_guid, context.caster_level, target_guid, spell_id,
          extra_attack?: context.extra_attack?,
          hit_context: context
        )

      {state, [event]}
    end
  end

  def apply(state, %CastContext{} = context, spell, %Effect{type: :dummy} = effect, now) do
    with [] <- pet_aura_events(state, context, spell),
         [] <- vmangos_script_events(state, context, spell) do
      case Semantics.rules(spell).dummy do
        :life_tap -> Warlock.life_tap(state, context, spell, effect, now)
        dummy_effect -> apply_class_dummy(state, context, spell, effect, dummy_effect, now)
      end
    else
      events -> {state, events}
    end
  end

  def apply(state, %CastContext{}, spell, %Effect{type: :script_effect}, _now) do
    case Warlock.healthstone_item(state, spell) do
      item_id when is_integer(item_id) and item_id > 0 -> {state, [Effects.create_item(item_id, 1)]}
      _ -> {state, []}
    end
  end

  def apply(state, _context, _spell, _effect, _now), do: {state, []}

  defp trigger_target_guid(state, %CastContext{} = context, %Effect{implicit_target_a: :caster})
       when state.object.guid != context.caster_guid do
    context.caster_guid
  end

  defp trigger_target_guid(state, _context, _effect), do: state.object.guid

  defp apply_class_dummy(state, context, spell, effect, :execute, now) do
    DamageHeal.execute(state, context, spell, effect, now)
  end

  defp apply_class_dummy(state, context, _spell, _effect, :berserking, _now)
       when state.object.guid == context.caster_guid do
    Racial.berserking(state)
  end

  defp apply_class_dummy(state, context, spell, effect, :blood_fury, _now)
       when state.object.guid == context.caster_guid do
    Racial.blood_fury(state, Amount.roll(spell, effect, context))
  end

  defp apply_class_dummy(state, _context, _spell, _effect, :shapeshift_cleanse, now) do
    Aura.remove_spells(state, Shapeshift.removable_spells(state.unit.auras || []), now)
  end

  defp apply_class_dummy(state, _context, _spell, _effect, :silithyst_pickup, now), do: Silithyst.pickup(state, now)

  defp apply_class_dummy(state, _context, _spell, _effect, :silithyst_pvp, now),
    do: {Silithyst.refresh_pvp(state, now), []}

  defp apply_class_dummy(
         state,
         %CastContext{cast_item_guid: item_guid} = context,
         _spell,
         _effect,
         {:guardian_trinket, spell_id},
         _now
       )
       when is_integer(item_guid) and state.object.guid == context.caster_guid do
    event =
      Effects.trigger_spell(context.caster_guid, context.caster_level, context.caster_guid, spell_id,
        cast_item_guid: item_guid
      )

    {state, [event]}
  end

  defp apply_class_dummy(state, context, _spell, _effect, :last_stand, _now) do
    event =
      Effects.trigger_spell(
        context.caster_guid,
        context.caster_level,
        state.object.guid,
        Scripts.last_stand_health_buff_id()
      )

    {state, [event]}
  end

  defp apply_class_dummy(state, context, _spell, _effect, :tame_beast_completion, _now) do
    event =
      Effects.trigger_spell(
        context.caster_guid,
        context.caster_level,
        state.object.guid,
        Scripts.tame_beast_ownership_spell_id()
      )

    {state, [event]}
  end

  defp apply_class_dummy(state, _context, _spell, _effect, :preparation, _now) do
    {Cooldowns.reset_family(state, Rogue.spell_family()), []}
  end

  defp apply_class_dummy(state, _context, spell, _effect, :hunter_cooldowns, _now) do
    {Hunter.reset_cooldowns(state, spell), []}
  end

  defp apply_class_dummy(state, _context, spell, _effect, :druid_enrage, _now) do
    {state, List.wrap(Druid.enrage_event(state, spell))}
  end

  defp apply_class_dummy(state, _context, _spell, _effect, :mage_cold_snap, _now) do
    {Cooldowns.reset_matching(state, &Mage.frost_cooldown?/1), []}
  end

  defp apply_class_dummy(state, context, _spell, _effect, {:holy_shock, spell_ids}, _now) do
    spell_id = if context.target_hostile?, do: spell_ids.damage, else: spell_ids.heal

    {state,
     [
       Effects.trigger_spell(context.caster_guid, context.caster_level, state.object.guid, spell_id,
         hit_context: context
       )
     ]}
  end

  defp apply_class_dummy(state, context, _spell, effect, :judgement_of_command, _now) do
    spell_id = Effect.damage_roll(effect)

    if spell_id > 1 do
      {state,
       [
         Effects.trigger_spell(context.caster_guid, context.caster_level, state.object.guid, spell_id,
           hit_context: context
         )
       ]}
    else
      {state, []}
    end
  end

  defp apply_class_dummy(state, _context, _spell, _effect, _unscripted, _now), do: {state, []}

  defp pet_aura_events(%Character{} = state, %CastContext{} = context, %Spell{id: spell_id}) do
    with pet_guid when is_integer(pet_guid) <- Character.controlled_guid(state),
         [_link | _rest] = aura_ids <- SpellPetAuraLoader.pet_aura_ids(spell_id, Guid.entry(pet_guid)) do
      Enum.map(aura_ids, fn aura_id ->
        Effects.trigger_spell(pet_guid, context.caster_level, pet_guid, aura_id, triggered_by_spell_id: spell_id)
      end)
    else
      _no_pet -> []
    end
  end

  defp pet_aura_events(
         %{object: %{guid: pet_guid}, internal: %{pet: %{owner_guid: owner_guid}}} = state,
         %CastContext{},
         %Spell{id: spell_id}
       )
       when is_integer(owner_guid) do
    case SpellPetAuraLoader.pet_aura_ids(spell_id, Guid.entry(pet_guid)) do
      [_link | _rest] = aura_ids ->
        Enum.map(aura_ids, fn aura_id ->
          Effects.trigger_spell(pet_guid, state.unit.level || 1, pet_guid, aura_id, triggered_by_spell_id: spell_id)
        end)

      _no_links ->
        []
    end
  end

  defp pet_aura_events(_state, _context, _spell), do: []

  defp vmangos_script_events(state, %CastContext{} = context, %Spell{script_steps: steps}) when is_list(steps) do
    Enum.flat_map(steps, fn
      %ScriptStep{command: :cast_spell, delay_ms: 0} = step -> vmangos_cast_event(state, context, step)
      _step -> []
    end)
  end

  defp vmangos_script_events(_state, _context, _spell), do: []

  defp vmangos_cast_event(state, %CastContext{} = context, %ScriptStep{} = step) do
    with spell_id when is_integer(spell_id) <- ScriptStep.cast_spell_id(step),
         {source_guid, target_guid} when is_integer(source_guid) and is_integer(target_guid) <-
           script_guids(state.object.guid, context.caster_guid, step) do
      source_level = if source_guid == state.object.guid, do: state.unit.level || 1, else: context.caster_level
      [Effects.trigger_spell(source_guid, source_level, target_guid, spell_id)]
    else
      _ -> []
    end
  end

  defp script_guids(target_guid, caster_guid, %ScriptStep{swap_initial?: true} = step) do
    script_target(step, target_guid, caster_guid)
  end

  defp script_guids(target_guid, caster_guid, %ScriptStep{} = step) do
    script_target(step, caster_guid, target_guid)
  end

  defp script_target(%ScriptStep{target_type: :provided, target_self?: true}, source_guid, _target_guid),
    do: {source_guid, source_guid}

  defp script_target(%ScriptStep{target_type: :provided}, source_guid, target_guid), do: {source_guid, target_guid}
  defp script_target(_step, _source_guid, _target_guid), do: nil
end
