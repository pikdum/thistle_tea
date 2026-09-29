defmodule ThistleTea.Game.Core.Spell.SpellEffect.Script do
  @moduledoc false

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Shapeshift
  alias ThistleTea.Game.Core.Aura.StackingProc
  alias ThistleTea.Game.Core.Class.Druid
  alias ThistleTea.Game.Core.Class.Hunter
  alias ThistleTea.Game.Core.Class.Mage
  alias ThistleTea.Game.Core.Class.Racial
  alias ThistleTea.Game.Core.Class.Rogue
  alias ThistleTea.Game.Core.Class.Warlock
  alias ThistleTea.Game.Core.Class.Warrior
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Item.Consumable
  alias ThistleTea.Game.Core.Item.ItemSpell
  alias ThistleTea.Game.Core.OutdoorPvp.Silithyst
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.PetTraining
  alias ThistleTea.Game.Core.Profession.Engineering
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Cooldowns
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Mount
  alias ThistleTea.Game.Core.Spell.Scripts
  alias ThistleTea.Game.Core.Spell.Semantics
  alias ThistleTea.Game.Core.Spell.SpellEffect.Amount
  alias ThistleTea.Game.Core.Spell.SpellEffect.DamageHeal
  alias ThistleTea.Game.Core.Spell.SpellTeaching

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

  def apply(%Character{} = state, %CastContext{}, _spell, %Effect{type: :quest_complete, misc_value: quest_id}, _now)
      when is_integer(quest_id) and quest_id > 0 do
    {state, [Effects.quest_event_credit(state.object.guid, quest_id)]}
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

      {state, trigger_events(spell, effect, event)}
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

  def apply(state, %CastContext{} = context, %Spell{id: 26_656}, %Effect{type: :script_effect, index: 0}, now) do
    Mount.summon_qiraji(state, context, now)
  end

  def apply(state, %CastContext{} = context, spell, %Effect{type: :script_effect}, now) do
    cond do
      aura_id = StackingProc.removal_spell(spell) -> Aura.remove_stack(state, aura_id, now)
      item_id = Warlock.healthstone_item(state, spell) -> {state, [Effects.create_item(item_id, 1)]}
      true -> {state, database_script_events(state, context, spell.script_steps)}
    end
  end

  def apply(state, _context, _spell, _effect, _now), do: {state, []}

  defp trigger_events(spell, effect, event) do
    case Scripts.trigger_chance(spell, effect) do
      {chance, total} -> [%Effects.RandomChoice{choices: [{chance, [event]}, {total - chance, []}]}]
      nil -> [event]
    end
  end

  defp database_script_events(state, %CastContext{caster_guid: guid}, [_ | _] = steps)
       when is_integer(guid) and guid > 0 do
    if state.object.guid == guid,
      do: [Effects.script_steps(steps, guid, 0)],
      else: [Effects.forward_script_steps(guid, steps, state.object.guid)]
  end

  defp database_script_events(_state, _context, _steps), do: []

  defp trigger_target_guid(state, %CastContext{} = context, %Effect{implicit_target_a: :caster})
       when state.object.guid != context.caster_guid do
    context.caster_guid
  end

  defp trigger_target_guid(state, _context, _effect), do: state.object.guid

  defp apply_class_dummy(state, context, _spell, %Effect{index: 0}, :six_demon_bag, _now) do
    ItemSpell.six_demon_bag(state, context)
  end

  defp apply_class_dummy(state, context, _spell, %Effect{index: 0}, :net_o_matic, _now) do
    Engineering.net_o_matic(state, context)
  end

  defp apply_class_dummy(state, context, _spell, %Effect{index: 0}, :universal_remote, _now) do
    Engineering.universal_remote(state, context)
  end

  defp apply_class_dummy(state, context, _spell, %Effect{index: 0}, :mind_control_cap, _now) do
    Engineering.mind_control_cap(state, context)
  end

  defp apply_class_dummy(state, context, _spell, %Effect{index: 0}, :goblin_bomb, _now) do
    Engineering.goblin_bomb(state, context)
  end

  defp apply_class_dummy(state, context, _spell, %Effect{index: 0}, :gnomish_transporter, _now) do
    Engineering.gnomish_transporter(state, context)
  end

  defp apply_class_dummy(state, context, _spell, %Effect{index: 0}, :transporter_arrival, _now) do
    Engineering.transporter_arrival(state, context)
  end

  defp apply_class_dummy(state, context, _spell, %Effect{index: 0}, :reindeer_transformation, now) do
    Mount.reindeer(state, context, now)
  end

  defp apply_class_dummy(%Mob{unit: %{health: 0}} = state, _context, _spell, _effect, :capture_corpse, _now) do
    {state, [Effects.despawn_self(1_000, 0)]}
  end

  defp apply_class_dummy(state, context, spell, effect, :execute, now) do
    DamageHeal.execute(state, context, spell, effect, now)
  end

  defp apply_class_dummy(state, context, _spell, %Effect{index: 0}, {:random_consumable, kind}, _now) do
    {state, Consumable.outcome(state, context, kind)}
  end

  defp apply_class_dummy(state, context, _spell, %Effect{index: 0}, {:trigger_spell, id}, _now) do
    event =
      Effects.trigger_spell(context.caster_guid, context.caster_level, state.object.guid, id,
        cast_item_guid: context.cast_item_guid,
        hit_context: context
      )

    {state, [event]}
  end

  defp apply_class_dummy(state, context, _spell, _effect, :deep_wounds, _now) do
    Warrior.deep_wounds(state, context)
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

  defp pet_aura_events(%Character{} = state, %CastContext{} = context, %Spell{id: spell_id} = spell) do
    with pet_guid when is_integer(pet_guid) <- Character.controlled_guid(state),
         [_link | _rest] = aura_ids <- Spell.pet_aura_ids(spell, Guid.entry(pet_guid)) do
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
         %Spell{id: spell_id} = spell
       )
       when is_integer(owner_guid) do
    case Spell.pet_aura_ids(spell, Guid.entry(pet_guid)) do
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
