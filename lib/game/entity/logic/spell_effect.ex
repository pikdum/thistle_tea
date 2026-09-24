defmodule ThistleTea.Game.Entity.Logic.SpellEffect do
  @moduledoc """
  Applies a cast spell's effects (damage, healing, auras, item creation, …) to
  a target entity, returning the updated entity and the events to emit.
  """
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CombatSkills
  alias ThistleTea.Game.Entity.Logic.ComboPoints
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.CreatureImmunity
  alias ThistleTea.Game.Entity.Logic.Critter
  alias ThistleTea.Game.Entity.Logic.DamageImmunity
  alias ThistleTea.Game.Entity.Logic.EffectImmunity
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.MechanicResistance
  alias ThistleTea.Game.Entity.Logic.PetTraining
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Aura, as: AuraEffects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.DamageHeal
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Honor, as: HonorEffects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Inventory, as: InventoryEffects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Movement, as: MovementEffects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Reputation, as: ReputationEffects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Resource, as: ResourceEffects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Script, as: ScriptEffects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.SummonControl, as: SummonControlEffects
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Entity.Logic.Totems
  alias ThistleTea.Game.Entity.Logic.Warrior
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Chain
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Scripts
  alias ThistleTea.Game.Spell.Semantics

  @dead_target_effects [:resurrect, :resurrect_new, :durability_damage, :durability_damage_percent]

  @weapon_effect_types [:weapon_damage, :weapon_damage_noschool, :normalized_weapon_damage, :weapon_percent_damage]

  defmodule Resolution do
    @moduledoc "A recipient's spell outcome and filtered effects, resolved once before combat entry."
    @enforce_keys [:context, :spell, :outcome, :kind]
    defstruct [:context, :spell, :outcome, :kind, :melee_result]
  end

  def receive(target, %CastContext{} = context, %Spell{} = spell, now) when is_integer(now) do
    apply_prepared(target, prepare(target, context, spell), now)
  end

  def receive(target, caster_guid, %Spell{} = spell, now) when is_integer(caster_guid) and is_integer(now) do
    receive(target, %CastContext{caster_guid: caster_guid, caster_level: 1}, spell, now)
  end

  def receive(target, _context, _spell, _now), do: {target, []}

  def prepare(target, %CastContext{} = context, %Spell{} = spell) do
    resolution = %Resolution{context: context, spell: spell, outcome: :hit, kind: :effects}

    cond do
      context.proc_damage? and (target.unit.health || 0) <= 0 ->
        %{resolution | kind: :ignored, outcome: :none}

      immune_to_spell?(target, context, spell) ->
        %{resolution | kind: :immune, outcome: :immune}

      reflect_harmful_spell?(target, context, spell) ->
        %{resolution | kind: :reflect, outcome: :reflect}

      context.hit_outcome == :resist ->
        %{resolution | kind: :launch_resist, outcome: :resist}

      true ->
        prepare_effects(target, resolution)
    end
  end

  def apply_prepared(target, %Resolution{kind: :ignored}, _now), do: {target, []}

  def apply_prepared(target, %Resolution{kind: :immune, context: context, spell: spell}, _now) do
    {target, [Effects.spell_log_miss(context.caster_guid, target.object.guid, spell.id, :immune)]}
  end

  def apply_prepared(target, %Resolution{kind: :reflect, context: context, spell: spell}, now) do
    {target, reactions} =
      Aura.reactions(target, :spell_hit_taken, %{
        attacker_guid: context.caster_guid,
        spell: spell,
        proc_type: :take_harmful_spell,
        outcome: :reflect,
        damage: 0,
        now: now
      })

    reflected_context = %{
      context
      | target_guid: context.caster_guid,
        target_role: :other,
        target_hostile?: true,
        reflected_by_guid: target.object.guid,
        hit_outcome: :hit
    }

    {target,
     [
       Effects.spell_log_miss(context.caster_guid, target.object.guid, spell.id, :reflect),
       Effects.deliver_spell(context.caster_guid, reflected_context, spell)
     ] ++ reactions}
  end

  def apply_prepared(target, %Resolution{kind: :launch_resist, context: context, spell: spell}, now) do
    {target, skill_events} = CombatSkills.resolve(target, special_attack(context, spell), :resist)
    {target, reactions} = outcome_reactions(target, context, spell, :resist, now)

    {target,
     [Effects.spell_log_miss(context.caster_guid, target.object.guid, spell.id, :resist) | reactions] ++ skill_events}
  end

  def apply_prepared(target, %Resolution{context: context, spell: spell} = resolution, now) do
    {target, events} = apply_resolved_effects(target, resolution, now)
    target = if successful_hit?(events), do: Critter.spell_hit(target, context.caster_guid, spell, now), else: target
    {target, events}
  end

  defp prepare_effects(target, %Resolution{context: context, spell: spell} = resolution) do
    context = %{context | combo_retention_spell: ComboPoints.retention_spell(spell)}

    applicable =
      target
      |> applicable_effects(context, spell.effects)
      |> Chain.effects(context)
      |> Warrior.filter_target_effects(target.object.guid, context, spell)
      |> defer_combo_retention(context)

    spell = %{spell | effects: applicable}

    effects =
      Enum.reject(applicable, fn effect ->
        EffectImmunity.blocked?(target, spell, effect) or CreatureImmunity.effect?(target, context, spell, effect) or
          Totems.immune_effect?(target, context, spell, effect)
      end)

    if effects == [] and applicable != [] do
      %{resolution | context: context, spell: spell, kind: :immune, outcome: :immune}
    else
      context = %{context | target_guid: target.object.guid, spell: %{spell | effects: effects}}
      prepare_melee(target, %{resolution | context: context, spell: spell})
    end
  end

  defp prepare_melee(target, %Resolution{context: context} = resolution) do
    if melee_roll_required?(target, context, context.spell) do
      result = AttackTable.roll_special(target, special_attack(context, context.spell))
      resolution = %{resolution | kind: :melee, melee_result: result}

      if result.outcome in [:normal, :crit] do
        context = %{context | melee_crit?: result.crit?}
        prepare_resistance(target, %{resolution | context: context})
      else
        %{resolution | outcome: result.outcome}
      end
    else
      prepare_resistance(target, resolution)
    end
  end

  defp prepare_resistance(target, %Resolution{context: %CastContext{spell: spell} = context} = resolution) do
    resistance = MechanicResistance.projection(target)

    effects =
      Enum.reject(spell.effects, fn effect ->
        context.caster_guid != target.object.guid and Spell.harmful?(spell) and
          MechanicResistance.effect_resisted?(resistance, spell, effect, Math.random_int(0, 99))
      end)

    if effects == [] and spell.effects != [],
      do: %{resolution | outcome: :resist},
      else: %{resolution | context: %{context | spell: %{spell | effects: effects}}}
  end

  defp defer_combo_retention(effects, %CastContext{combo_retention_spell: nil}), do: effects
  defp defer_combo_retention(effects, _context), do: Enum.reject(effects, &ComboPoints.retention_effect?/1)

  def successful_hit?(events) when is_list(events) do
    Enum.all?(events, &(not is_struct(&1, Effects.SpellLogMiss)))
  end

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

  defp outcome_reactions(target, %CastContext{proc_damage?: true}, _spell, _outcome, _now), do: {target, []}

  defp outcome_reactions(target, %CastContext{caster_guid: caster_guid}, spell, outcome, now),
    do: receive_outcome(target, caster_guid, spell, outcome, now)

  defp immune_to_spell?(target, %CastContext{caster_guid: caster_guid} = context, %Spell{} = spell) do
    CreatureImmunity.spell?(target, context, spell) or
      (target.object.guid != caster_guid and Spell.harmful?(spell) and
         DamageImmunity.immune?(target, spell.school, spell))
  end

  defp reflect_harmful_spell?(target, %CastContext{caster_guid: caster_guid, reflected_by_guid: nil}, %Spell{} = spell) do
    target.object.guid != caster_guid and Spell.reflectable?(spell) and Aura.reflect_spell?(target, spell)
  end

  defp reflect_harmful_spell?(_target, _context, _spell), do: false

  defp applicable_effects(_target, %CastContext{target_role: :caster}, effects) do
    Enum.reject(effects, fn effect ->
      hostile_target_effect?(effect) or
        (pet_target_effect?(effect) and not caster_execution_effect?(effect)) or
        master_target_effect?(effect)
    end)
  end

  defp applicable_effects(_target, %CastContext{target_role: :pet}, effects) do
    Enum.reject(effects, &(caster_target_effect?(&1) or hostile_target_effect?(&1) or caster_execution_effect?(&1)))
  end

  defp applicable_effects(_target, %CastContext{target_role: :other, target_hostile?: hostile?}, effects) do
    Enum.reject(effects, fn effect ->
      caster_target_effect?(effect) or pet_target_effect?(effect) or
        (hostile? == false and hostile_target_effect?(effect) and not master_target_effect?(effect))
    end)
  end

  defp applicable_effects(%{object: %{guid: guid}}, %CastContext{caster_guid: guid}, effects) do
    Enum.reject(effects, &hostile_target_effect?/1)
  end

  defp applicable_effects(_target, _context, effects), do: Enum.reject(effects, &caster_target_effect?/1)

  defp caster_target_effect?(%Effect{type: :apply_area_aura}), do: false
  defp caster_target_effect?(%Effect{type: :summon_object_wild}), do: true

  defp caster_target_effect?(%Effect{} = effect) do
    (effect.implicit_target_a == :caster or effect.implicit_target_b == :caster) and
      not caster_trigger_effect?(effect)
  end

  defp caster_trigger_effect?(%Effect{type: :trigger_spell, implicit_target_a: :caster}), do: true
  defp caster_trigger_effect?(_effect), do: false

  defp caster_execution_effect?(%Effect{type: :dismiss_pet}), do: true
  defp caster_execution_effect?(%Effect{type: :summon_object_wild}), do: true
  defp caster_execution_effect?(%Effect{type: :summon_mini_pet}), do: true
  defp caster_execution_effect?(%Effect{type: :summon_guardian}), do: true
  defp caster_execution_effect?(%Effect{type: :summon_wild}), do: true
  defp caster_execution_effect?(effect), do: PetTraining.training_effect?(effect)

  defp pet_target_effect?(%Effect{} = effect) do
    effect.implicit_target_a == :pet or effect.implicit_target_b == :pet
  end

  defp master_target_effect?(%Effect{} = effect) do
    effect.implicit_target_a == :caster_master or effect.implicit_target_b == :caster_master
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
    Spell.harmful?(spell) and (Spell.melee_ability?(spell) or Spell.ranged_attack?(spell)) and
      target_guid != caster_guid
  end

  defp apply_resolved_effects(
         target,
         %Resolution{kind: :melee, context: context, melee_result: result} = resolution,
         now
       ) do
    {target, skill_events} = CombatSkills.resolve(target, special_attack(context, context.spell), result.outcome)
    {target, events} = receive_melee_result(target, resolution, now)
    {target, events ++ skill_events}
  end

  defp apply_resolved_effects(target, %Resolution{context: context} = resolution, now) do
    target |> apply_resisted_effects(resolution, now) |> with_bonus_threat(context)
  end

  defp receive_melee_result(target, %Resolution{context: context, melee_result: result} = resolution, now) do
    spell = context.spell

    case result.outcome do
      :resist ->
        {target, reactions} = receive_outcome(target, context.caster_guid, spell, :resist, now)
        {target, melee_avoid_events(target, context, spell, :resist) ++ reactions}

      outcome when outcome in [:miss, :dodge, :parry, :block] ->
        target = maybe_mark_defense(target, context.caster_guid, outcome, now)
        {target, reaction_events} = DamageHeal.avoided_melee_ability_reactions(target, context, spell, outcome, now)
        {target, melee_avoid_events(target, context, spell, outcome) ++ reaction_events}

      _hit ->
        {target, events} = apply_resisted_effects(target, resolution, now)

        events =
          if Spell.melee_ability?(spell) do
            events ++
              [
                Effects.attack_outcome(
                  context.caster_guid,
                  target.object.guid,
                  if(successful_hit?(events), do: result.outcome, else: :resist),
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
        if successful_hit?(events) do
          {Threat.add(target, context.caster_guid, flat * (context.threat_multiplier || 1.0)), events}
        else
          {target, events}
        end

      _no_bonus ->
        {target, events}
    end
  end

  defp apply_resisted_effects(target, %Resolution{outcome: :resist, context: context}, now) do
    spell = context.spell
    {target, reactions} = outcome_reactions(target, context, spell, :resist, now)
    {target, [Effects.spell_log_miss(context.caster_guid, target.object.guid, spell.id, :resist) | reactions]}
  end

  defp apply_resisted_effects(target, %Resolution{context: context}, now) do
    apply_effects(target, context, context.spell.effects, [], now)
  end

  defp apply_effects(target, context, effects, events, now) do
    apply_effects(target, context, effects, events, MapSet.new(), now)
  end

  defp apply_effects(target, _context, [], events, _applied, _now), do: {target, events}

  defp apply_effects(target, context, effects, events, applied, now) do
    effects =
      if Core.dead?(target) do
        Enum.filter(effects, &match?(%Effect{type: type} when type in @dead_target_effects, &1))
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
        spell_id = Scripts.channel_trigger_spell_id(context.spell, effect.trigger_spell_id)
        target_guid = channel_trigger_target(target, context)

        event =
          Effects.trigger_spell(context.caster_guid, context.caster_level, target_guid, spell_id, hit_context: context)

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

  defp channel_trigger_target(%{object: %{guid: caster}, unit: %{channel_object: guid}}, %CastContext{
         caster_guid: caster
       })
       when is_integer(guid) and guid > 0 and guid != caster, do: guid

  defp channel_trigger_target(target, _context), do: target.object.guid

  defp apply_effect(state, context, spell, %Effect{} = effect, now) do
    case Semantics.effect_rule(effect) do
      %Semantics.DamageHeal{} -> DamageHeal.apply(state, context, spell, effect, now)
      %Semantics.Aura{} -> AuraEffects.apply(state, context, spell, effect, now)
      %Semantics.Resource{} -> ResourceEffects.apply(state, context, spell, effect, now)
      %Semantics.Movement{} -> MovementEffects.apply(state, context, spell, effect, now)
      rule -> apply_secondary_effect(rule, state, context, spell, effect, now)
    end
  end

  defp apply_secondary_effect(%Semantics.Inventory{}, state, context, spell, effect, now),
    do: InventoryEffects.apply(state, context, spell, effect, now)

  defp apply_secondary_effect(%Semantics.Script{}, state, context, spell, effect, now),
    do: ScriptEffects.apply(state, context, spell, effect, now)

  defp apply_secondary_effect(%Semantics.Reputation{}, state, context, spell, effect, now),
    do: ReputationEffects.apply(state, context, spell, effect, now)

  defp apply_secondary_effect(%Semantics.Honor{}, state, context, spell, effect, now),
    do: HonorEffects.apply(state, context, spell, effect, now)

  defp apply_secondary_effect(%Semantics.SummonControl{}, state, context, spell, effect, now),
    do: SummonControlEffects.apply(state, context, spell, effect, now)

  defp apply_secondary_effect(_rule, state, _context, _spell, _effect, _now), do: {state, []}

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

  defp special_attack(%CastContext{} = context, spell) do
    %{
      caster: context.caster_guid,
      caster_owner_guid: context.caster_owner_guid,
      caster_level: context.caster_level,
      caster_player?: context.caster_type == :player,
      caster_attack_skill: context.attack_skill,
      weapon_skill_id: context.weapon_skill_id,
      skill_training?:
        spell.equipped_item_class == 2 and Spell.harmful?(spell) and
          (Spell.melee_ability?(spell) or Spell.ranged_attack?(spell)),
      hit_chance_bonus: context.hit_chance_bonus,
      crit_chance: context.melee_crit_chance,
      caster_position: attack_position(context.caster_position),
      spell_school_mask: Spell.school_mask(spell),
      mechanic: spell.mechanic,
      block_allowed?: Spell.attribute?(spell, :completely_blocked),
      ranged?: Spell.ranged_attack?(spell)
    }
  end

  defp attack_position({_map, x, y, z}), do: {x, y, z}
  defp attack_position(_position), do: nil
end
