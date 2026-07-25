defmodule ThistleTea.Game.Entity.Logic.SpellEffect do
  @moduledoc """
  Applies a cast spell's effects (damage, healing, auras, item creation, …) to
  a target entity, returning the updated entity and the events to emit.
  """
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.Rogue
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Aura, as: AuraEffects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.DamageHeal
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Inventory, as: InventoryEffects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Movement, as: MovementEffects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Resource, as: ResourceEffects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Script, as: ScriptEffects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.SummonControl, as: SummonControlEffects
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Entity.Logic.Warrior
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Semantics

  @resurrect_effects [:resurrect, :resurrect_new]

  @weapon_effect_types [:weapon_damage, :weapon_damage_noschool, :normalized_weapon_damage, :weapon_percent_damage]

  def receive(target, %CastContext{} = context, %Spell{} = spell, now) when is_integer(now) do
    cond do
      immune_to_harmful_spell?(target, context, spell) ->
        {target, [Effects.spell_log_miss(context.caster_guid, target.object.guid, spell.id, :immune)]}

      reflect_harmful_spell?(target, context, spell) ->
        reflected_context = %{
          context
          | target_guid: context.caster_guid,
            target_role: :other,
            target_hostile?: true,
            reflected_by_guid: target.object.guid
        }

        {target,
         [
           Effects.spell_log_miss(context.caster_guid, target.object.guid, spell.id, :reflect),
           Effects.deliver_spell(context.caster_guid, reflected_context, spell)
         ]}

      true ->
        effects =
          target
          |> applicable_effects(context, spell.effects)
          |> Warrior.filter_target_effects(target.object.guid, context, spell)

        spell = %{spell | effects: effects}
        context = %{context | target_guid: target.object.guid, spell: spell}

        if melee_roll_required?(target, context, spell) do
          receive_melee_ability(target, context, spell, now)
        else
          target
          |> apply_effects(context, effects, [], now)
          |> with_bonus_threat(context)
        end
    end
  end

  def receive(target, caster_guid, %Spell{} = spell, now) when is_integer(caster_guid) and is_integer(now) do
    receive(target, %CastContext{caster_guid: caster_guid, caster_level: 1}, spell, now)
  end

  def receive(target, _context, _spell, _now), do: {target, []}

  def receive_outcome(target, caster_guid, %Spell{} = spell, :resist, now)
      when is_integer(caster_guid) and is_integer(now) do
    Aura.reactions(target, :spell_hit_taken, %{
      attacker_guid: caster_guid,
      spell: spell,
      proc_type: :take_harmful_spell,
      outcome: :resist,
      damage: 0,
      now: now
    })
  end

  def receive_outcome(target, _caster_guid, _spell, _outcome, _now), do: {target, []}

  defp immune_to_harmful_spell?(target, %CastContext{caster_guid: caster_guid}, %Spell{} = spell) do
    target.object.guid != caster_guid and Spell.harmful?(spell) and Aura.school_immune?(target, spell.school)
  end

  defp reflect_harmful_spell?(target, %CastContext{caster_guid: caster_guid}, %Spell{} = spell) do
    target.object.guid != caster_guid and Spell.harmful?(spell) and Aura.reflect_spell?(target, spell)
  end

  defp applicable_effects(_target, %CastContext{target_role: :caster}, effects) do
    Enum.reject(effects, &(hostile_target_effect?(&1) or pet_target_effect?(&1)))
  end

  defp applicable_effects(_target, %CastContext{target_role: :pet}, effects) do
    Enum.reject(effects, &(caster_target_effect?(&1) or hostile_target_effect?(&1)))
  end

  defp applicable_effects(_target, %CastContext{target_role: :other}, effects) do
    Enum.reject(effects, &(caster_target_effect?(&1) or pet_target_effect?(&1)))
  end

  defp applicable_effects(%{object: %{guid: guid}}, %CastContext{caster_guid: guid}, effects) do
    Enum.reject(effects, &hostile_target_effect?/1)
  end

  defp applicable_effects(_target, _context, effects), do: Enum.reject(effects, &caster_target_effect?/1)

  defp caster_target_effect?(%Effect{type: :apply_area_aura}), do: false

  defp caster_target_effect?(%Effect{} = effect) do
    (effect.implicit_target_a == :caster or effect.implicit_target_b == :caster) and
      not caster_trigger_effect?(effect)
  end

  defp caster_trigger_effect?(%Effect{type: :trigger_spell, implicit_target_a: :caster}), do: true
  defp caster_trigger_effect?(_effect), do: false

  defp pet_target_effect?(%Effect{} = effect) do
    effect.implicit_target_a == :pet or effect.implicit_target_b == :pet
  end

  defp hostile_target_effect?(%Effect{} = effect) do
    effect.implicit_target_a in [
      :target_enemy,
      :aoe_enemy_at_caster,
      :aoe_enemy_in_cone,
      :aoe_enemy_at_channel,
      :aoe_enemy_at_dest
    ] or
      effect.implicit_target_b in [
        :target_enemy,
        :aoe_enemy_at_caster,
        :aoe_enemy_in_cone,
        :aoe_enemy_at_channel,
        :aoe_enemy_at_dest
      ]
  end

  defp melee_roll_required?(%{object: %{guid: target_guid}}, %CastContext{caster_guid: caster_guid}, spell) do
    (Spell.melee_ability?(spell) or ranged_weapon_ability?(spell)) and target_guid != caster_guid
  end

  defp ranged_weapon_ability?(%Spell{effects: effects} = spell) do
    Spell.ranged_ability?(spell) and Enum.any?(effects, &(&1.type in @weapon_effect_types))
  end

  defp receive_melee_ability(target, %CastContext{} = context, spell, now) do
    result = AttackTable.roll_special(target, special_attack(context, spell))

    case result.outcome do
      outcome when outcome in [:miss, :dodge, :parry, :block] ->
        target = maybe_mark_defense(target, context.caster_guid, outcome, now)
        {target, reaction_events} = DamageHeal.avoided_melee_ability_reactions(target, context, spell, outcome, now)
        {target, melee_avoid_events(target, context, spell, outcome) ++ reaction_events}

      _hit ->
        context = %{context | melee_crit?: result.crit?}

        {target, events} = apply_effects(target, context, spell.effects, [], now)

        events =
          if rogue_feedback_spell?(spell) do
            events ++
              [
                Effects.attack_outcome(
                  context.caster_guid,
                  target.object.guid,
                  result.outcome,
                  dealt_damage(events),
                  spell.id,
                  dealt_proc_damage(events)
                )
              ]
          else
            events
          end

        with_bonus_threat({target, events}, context)
    end
  end

  defp with_bonus_threat({target, events}, %CastContext{} = context) do
    case context.spell_threat do
      %{threat: flat} when is_number(flat) and flat > 0 ->
        {Threat.add(target, context.caster_guid, flat * (context.threat_multiplier || 1.0)), events}

      _no_bonus ->
        {target, events}
    end
  end

  defp apply_effects(target, context, effects, events, now) do
    apply_effects(target, context, effects, events, MapSet.new(), now)
  end

  defp apply_effects(target, _context, [], events, _applied, _now), do: {target, events}

  defp apply_effects(target, context, effects, events, applied, now) do
    effects =
      if Core.dead?(target) do
        Enum.filter(effects, &match?(%Effect{type: type} when type in @resurrect_effects, &1))
      else
        effects
      end

    do_apply_effects(target, context, effects, events, applied, now)
  end

  defp do_apply_effects(target, _context, [], events, _applied, _now), do: {target, events}

  defp do_apply_effects(target, context, [effect | rest], events, applied, now) do
    {target, events, applied} = apply_one_effect(target, context, effect, events, applied, now)
    apply_effects(target, context, rest, events, applied, now)
  end

  defp apply_one_effect(target, context, effect, events, applied, now) do
    cond do
      channel_ticked_trigger?(context.spell, effect) ->
        event =
          Effects.trigger_spell(context.caster_guid, context.caster_level, target.object.guid, effect.trigger_spell_id)

        {target, events ++ [event], applied}

      aura_effect?(effect) ->
        if MapSet.member?(applied, :aura) do
          {target, events, applied}
        else
          {target, aura_events} = AuraEffects.apply_group(target, context, now)
          {target, events ++ aura_events, MapSet.put(applied, :aura)}
        end

      weapon_effect?(effect) ->
        if MapSet.member?(applied, :weapon) do
          {target, events, applied}
        else
          {target, weapon_events} = DamageHeal.apply_weapon_group(target, context, context.spell, now)
          {target, events ++ weapon_events, MapSet.put(applied, :weapon)}
        end

      true ->
        {target, effect_events} = apply_effect(target, context, context.spell, effect, now)
        {target, events ++ effect_events, applied}
    end
  end

  defp aura_effect?(%Effect{type: type}), do: type in [:apply_aura, :apply_area_aura]

  defp weapon_effect?(%Effect{type: type}), do: type in @weapon_effect_types

  defp channel_ticked_trigger?(spell, %Effect{} = effect), do: Spell.channel_ticked_effect?(spell, effect)
  defp channel_ticked_trigger?(_spell, _effect), do: false

  defp apply_effect(state, context, spell, %Effect{} = effect, now) do
    case Semantics.effect_rule(effect) do
      %Semantics.DamageHeal{} -> DamageHeal.apply(state, context, spell, effect, now)
      %Semantics.Aura{} -> AuraEffects.apply(state, context, spell, effect, now)
      %Semantics.Resource{} -> ResourceEffects.apply(state, context, spell, effect, now)
      %Semantics.Movement{} -> MovementEffects.apply(state, context, spell, effect, now)
      %Semantics.Inventory{} -> InventoryEffects.apply(state, context, spell, effect, now)
      %Semantics.Script{} -> ScriptEffects.apply(state, context, spell, effect, now)
      %Semantics.SummonControl{} -> SummonControlEffects.apply(state, context, spell, effect, now)
      _rule -> {state, []}
    end
  end

  defp maybe_mark_defense(state, attacker_guid, outcome, now) when outcome in [:dodge, :parry, :block] do
    Reactive.mark_defense(state, attacker_guid, outcome, now)
  end

  defp maybe_mark_defense(state, _attacker_guid, _outcome, _now), do: state

  defp melee_avoid_events(%{object: %{guid: target_guid}}, %CastContext{} = context, spell, outcome) do
    [
      Effects.spell_log_miss(context.caster_guid, target_guid, spell.id, outcome),
      Effects.attack_outcome(context.caster_guid, target_guid, outcome, 0, spell.id)
    ]
  end

  defp dealt_damage(events) do
    Enum.reduce(events, 0, fn
      %Effects.SpellDamage{damage: damage, absorbed: absorbed}, acc when is_integer(damage) ->
        acc + max(damage - (absorbed || 0), 0)

      _event, acc ->
        acc
    end)
  end

  defp dealt_proc_damage(events) do
    Enum.reduce(events, 0, fn
      %Effects.SpellDamage{proc_damage: proc_damage, damage: damage, absorbed: absorbed}, acc
      when is_integer(proc_damage) and is_integer(damage) and damage > 0 ->
        acc + round(proc_damage * max(damage - (absorbed || 0), 0) / damage)

      %Effects.SpellDamage{damage: damage, absorbed: absorbed}, acc when is_integer(damage) ->
        acc + max(damage - (absorbed || 0), 0)

      _event, acc ->
        acc
    end)
  end

  defp rogue_feedback_spell?(%Spell{} = spell) do
    Rogue.rogue_spell?(spell)
  end

  defp special_attack(%CastContext{} = context, spell) do
    %{
      caster: context.caster_guid,
      caster_level: context.caster_level,
      caster_player?: context.caster_type == :player,
      caster_attack_skill: context.attack_skill,
      hit_chance_bonus: context.hit_chance_bonus,
      crit_chance: context.melee_crit_chance,
      caster_position: attack_position(context.caster_position),
      spell_school_mask: Spell.school_mask(spell),
      block_allowed?: Spell.attribute?(spell, :completely_blocked),
      ranged?: Spell.ranged_ability?(spell)
    }
  end

  defp attack_position({_map, x, y, z}), do: {x, y, z}
  defp attack_position(_position), do: nil
end
