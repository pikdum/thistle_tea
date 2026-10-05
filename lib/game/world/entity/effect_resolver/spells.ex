defmodule ThistleTea.Game.World.Entity.EffectResolver.Spells do
  @moduledoc false

  alias ThistleTea.Game.Core.Aura.ProcDamage
  alias ThistleTea.Game.Core.Aura.StealthDetection
  alias ThistleTea.Game.Core.Aura.TriggeredLifetime
  alias ThistleTea.Game.Core.Class.Warrior
  alias ThistleTea.Game.Core.Combat.CombatTimer
  alias ThistleTea.Game.Core.Combat.ExtraAttacks
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Movement.Charge
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Area
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Chain
  alias ThistleTea.Game.Core.Spell.Combat, as: SpellCombat
  alias ThistleTea.Game.Core.Spell.Focus
  alias ThistleTea.Game.Core.Spell.LocationTargets
  alias ThistleTea.Game.Core.Spell.ObjectTargets
  alias ThistleTea.Game.Core.Spell.ProcOrigin
  alias ThistleTea.Game.Core.Spell.Scripts
  alias ThistleTea.Game.Core.Spell.SendEvent
  alias ThistleTea.Game.Core.Spell.SharedDamage
  alias ThistleTea.Game.Core.Spell.SpellResist
  alias ThistleTea.Game.Core.Spell.SpellTarget
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.Spell.UnitTargets
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity.EffectResolver.Movement
  alias ThistleTea.Game.World.Entity.EffectResolver.Pvp
  alias ThistleTea.Game.World.Entity.EffectResolver.SpellLaunch
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Reaction
  alias ThistleTea.Game.World.Spell.SpellAreas
  alias ThistleTea.Game.World.Spell.SpellFocus
  alias ThistleTea.Game.World.Spell.SpellObjects
  alias ThistleTea.Game.World.Spell.SpellRequirements
  alias ThistleTea.Game.World.Spell.SpellTargetResolver
  alias ThistleTea.Game.World.System.SpellMagnets

  @heal_threat_radius 100.0

  def resolve(entity, %Effects.SummonMount{} = effect) do
    spell_id =
      if MapTemplate.mount_allowed?(entity.internal.world.map_id),
        do: effect.allowed_spell_id,
        else: effect.restricted_spell_id

    trigger =
      Effects.trigger_spell(entity.object.guid, entity.unit.level, entity.object.guid, spell_id,
        cast_item_guid: effect.cast_item_guid
      )

    resolve(entity, trigger)
  end

  def resolve(entity, %Effects.SpellGameObjectAction{target_guid: guid} = effect) do
    world = entity.internal.world

    case World.position(guid) do
      {^world, _, _, _} ->
        [
          %Effects.ApplyGameObjectAction{
            target_guid: guid,
            source_guid: entity.object.guid,
            world: world,
            spell_id: effect.spell_id,
            action: effect.action
          }
        ]

      _ ->
        []
    end
  end

  def resolve(entity, %Effects.CheckCastRequirements{cast: cast, now: now}) do
    [
      %Effects.CastRequirementsResolved{
        cast: cast,
        now: now,
        requirements: SpellRequirements.resolve(entity, cast.spell, cast.targets, cast_item_guid: cast.cast_item_guid)
      }
    ]
  end

  def resolve(entity, %Effects.ProcDamage{target_guid: target_guid, spell: spell, effect_index: index}) do
    target =
      Metadata.query(target_guid, [
        :alive?,
        :level,
        :aoe_avoidance,
        :attacker_spell_hit_chance,
        :mechanic_resistance,
        :school_resistances,
        :no_spell_defense?
      ])

    with %{alive?: true} <- target,
         {damage_spell, context} <- ProcDamage.prepare(entity, spell, index, target_guid) do
      hit? = ProcDamage.hit?(entity, spell, target, Guid.entity_type(target_guid) == :player)
      context = %{context | hit_outcome: if(hit?, do: :hit, else: :resist)}
      resolved_delivery(entity, Effects.deliver_spell(target_guid, context, damage_spell))
    else
      _invalid -> []
    end
  end

  def resolve(entity, %Effects.DeliverSpell{delay_ms: nil} = effect) do
    resolved_delivery(entity, effect)
  end

  def resolve(_entity, %Effects.DeliverSpell{} = effect), do: [effect]

  def resolve(entity, %Effects.SpellDamage{damage: damage, source_guid: source, target_guid: target} = effect)
      when is_number(damage) and damage > 0 and is_integer(source) and source > 0 and source != target do
    if SpellCombat.damage_contact?(effect.spell, effect.periodic?, effect.triggered_by_proc?) do
      contact = %Effects.SpellContact{
        target_guid: source,
        other_guid: target,
        other_uses_timer?: timed_target?(entity, target),
        decision: %SpellCombat{combat?: true},
        now: Time.now()
      }

      contacts = if Guid.entity_type(source) in [:player, :mob, :pet], do: [contact], else: []
      contacts ++ Pvp.contacts(entity, source, target, :attack) ++ [effect]
    else
      [effect]
    end
  end

  def resolve(entity, %Effects.SpellHeal{periodic?: true} = effect) do
    Pvp.contacts(entity, effect.source_guid, effect.target_guid, :assist) ++ [effect]
  end

  def resolve(_entity, %Effects.SpellDamage{} = effect), do: [effect]
  def resolve(_entity, %Effects.SpellHeal{} = effect), do: [effect]

  def resolve(entity, %Effects.DeliverSpellToQuery{spell: %Spell{} = spell} = effect) do
    entity
    |> SpellTargetResolver.resolve_query(spell, effect.query, exclude_guids: effect.exclude_guids)
    |> Enum.flat_map(fn target_guid ->
      context = %CastContext{
        caster_guid: effect.source_guid,
        caster_level: effect.source_level,
        target_guid: target_guid,
        target_hostile?: Spell.requires_hostile_target?(spell),
        spell: spell
      }

      resolved_delivery(entity, Effects.deliver_spell(target_guid, context, spell))
    end)
  end

  def resolve(_entity, %Effects.DeliverSpellToQuery{}), do: []

  def resolve(entity, %Effects.HealThreat{} = effect) do
    entity
    |> World.nearby_mobs(@heal_threat_radius)
    |> Enum.map(fn {guid, _distance} ->
      Effects.deliver_heal_threat(guid, effect.source_guid, effect.target_guid, effect.amount)
    end)
  end

  def resolve(%{object: %{guid: guid}}, %Effects.TriggerSpell{source_guid: source, resolve_targets?: true} = effect)
      when is_integer(source) and source != guid do
    [trigger_request(effect)]
  end

  def resolve(entity, %Effects.TriggerSpell{} = effect) do
    with %Spell{} = loaded <- trigger_spell(entity, effect.spell_id),
         %Spell{} = spell <- loaded |> scripted_proc_spell(effect) |> apply_trigger_override(effect),
         false <- effect.extra_attack? and ExtraAttacks.spell?(spell) do
      resolve_trigger(entity, effect, spell)
    else
      _missing -> []
    end
  end

  def resolved_delivery(entity, %Effects.DeliverSpell{} = effect) do
    context = target_hostility(entity, effect)

    context =
      if context.caster_guid == entity.object.guid and match?(%{unit: %Unit{}}, entity),
        do: %{context | caster_detection: StealthDetection.target_metadata(entity)},
        else: context

    [%{effect | cast_context: context, hostility_check: nil, delay_ms: projectile_delay_ms(entity, effect)}]
  end

  defp target_hostility(entity, %Effects.DeliverSpell{hostility_check: opts, target_guid: target, cast_context: context})
       when is_list(opts) do
    source = if context.caster_guid == entity.object.guid, do: entity, else: context.caster_guid
    %{context | target_hostile?: Reaction.valid_attack_target?(source, target, opts)}
  end

  defp target_hostility(_entity, %Effects.DeliverSpell{cast_context: context}), do: context

  defp timed_target?(%{object: %{guid: guid}} = entity, guid), do: CombatTimer.uses_timer?(entity)

  defp timed_target?(_entity, guid), do: CombatTimer.uses_timer?(Map.put(Metadata.get(guid) || %{}, :guid, guid))

  defp trigger_spell(%{internal: %{spellbook: spellbook}}, id) when is_map(spellbook),
    do: Map.get(spellbook, id) || SpellLoader.cached(id)

  defp trigger_spell(_entity, id), do: SpellLoader.cached(id)

  defp resolve_trigger(entity, effect, spell) do
    if foreign_owner_required?(entity, effect, spell) do
      [trigger_request(effect)]
    else
      validate_trigger_focus(entity, effect, spell)
    end
  end

  defp trigger_request(%Effects.TriggerSpell{} = effect) do
    Effects.trigger_spell_request(effect.source_guid, effect.spell_id, effect.target_guid,
      base_points: effect.amount,
      effect_base_points: effect.effect_base_points,
      cast_item_guid: effect.cast_item_guid,
      effect_index: effect.slot,
      duration_ms: effect.duration_ms,
      resolve_targets?: true,
      requires_living_target?: effect.requires_living_target?,
      extra_attack?: effect.extra_attack?,
      triggered_by_spell_id: effect.triggering_spell_id,
      attack_hand: effect.attack_hand,
      hit_context: effect.hit_context,
      target_role: effect.target_role
    )
  end

  defp foreign_owner_required?(entity, effect, spell),
    do: casting_owner?(entity, effect.source_guid) and owner_requirements?(spell, effect.source_guid)

  defp casting_owner?(%{object: %{guid: guid}}, source_guid),
    do: is_integer(source_guid) and source_guid != guid and Guid.entity_type(source_guid) != :game_object

  defp owner_requirements?(spell, source_guid) do
    Enum.any?(spell.effects, &(&1.type == :charge)) or Spell.attribute?(spell, :channeled) or Chain.spell?(spell) or
      ObjectTargets.required?(spell) or target_requirements?(spell) or
      (Focus.required?(spell) and Guid.entity_type(source_guid) == :player)
  end

  defp target_requirements?(spell),
    do:
      UnitTargets.required?(spell) or LocationTargets.required?(spell) or Area.restricted?(spell) or
        SharedDamage.required?(spell)

  defp validate_trigger_focus(entity, effect, spell) do
    with :ok <- Focus.validate(entity, spell, SpellFocus.find(entity, spell)),
         :ok <- Area.validate(spell, SpellAreas.context(entity, spell)),
         :ok <- validate_trigger_reagents(entity, effect, spell) do
      entity |> resolve_trigger_delivery(effect, spell) |> pay_trigger_reagents(effect, spell)
    else
      {:error, reason} ->
        [Effects.spell_cast_failed(spell, reason)]
    end
  end

  defp validate_trigger_reagents(%Character{player: player}, %Effects.TriggerSpell{pays_reagents?: true}, %Spell{
         reagents: [_ | _] = reagents
       }) do
    if Enum.all?(reagents, fn {entry, count} -> Inventory.count_entry(player, entry, &ItemStore.get/1) >= count end),
      do: :ok,
      else: {:error, :reagents}
  end

  defp validate_trigger_reagents(_entity, _effect, _spell), do: :ok

  defp pay_trigger_reagents(effects, %Effects.TriggerSpell{pays_reagents?: true}, %Spell{reagents: [_ | _] = reagents}) do
    if Enum.any?(effects, &match?(%Effects.SpellGo{}, &1)),
      do: effects ++ [Effects.consume_reagents(reagents)],
      else: effects
  end

  defp pay_trigger_reagents(effects, _effect, _spell), do: effects

  defp resolve_trigger_delivery(entity, effect, spell) do
    cond do
      Spell.attribute?(spell, :channeled) ->
        resolve_triggered_channel(entity, effect, spell)

      UnitTargets.required?(spell) or LocationTargets.required?(spell) or SharedDamage.required?(spell) ->
        resolve_scripted_trigger(entity, effect, spell)

      effect.resolve_targets? or SpellTarget.area_targeted?(spell) or Chain.spell?(spell) ->
        resolve_area_trigger(entity, effect, spell)

      true ->
        resolve_single_trigger(entity, effect, spell)
    end
  end

  defp resolve_triggered_channel(entity, effect, spell) do
    case triggered_target(entity, effect, spell) do
      nil ->
        []

      guid ->
        selected_guid = if guid == entity.object.guid, do: effect.target_guid || guid, else: guid

        [
          %Effects.StartTriggeredChannel{
            spell: spell,
            targets: Target.unit(selected_guid),
            context: trigger_context(entity, %{effect | target_guid: guid}, spell),
            cast_item_guid: effect.cast_item_guid
          }
        ]
    end
  end

  defp resolve_single_trigger(entity, effect, spell) do
    case triggered_target(entity, effect, spell) do
      nil ->
        []

      target_guid ->
        target_guid = SpellMagnets.redirect(entity, spell, target_guid)
        effect = %{effect | target_guid: target_guid}
        target = Target.unit(target_guid)

        triggered_cast(entity, effect, spell, [target_guid], target)
    end
  end

  defp resolve_scripted_trigger(entity, effect, spell) do
    selection = Target.unit(effect.target_guid || entity.object.guid)
    requirements = SpellRequirements.resolve(entity, spell, selection)

    with :ok <- LocationTargets.validate(spell, requirements.locations),
         :ok <- UnitTargets.validate(spell, requirements.units),
         :ok <- ObjectTargets.validate(spell, requirements.objects) do
      selection =
        selection
        |> LocationTargets.apply(requirements.locations)
        |> UnitTargets.item_selection(requirements.units, effect.cast_item_guid)

      plan =
        SpellTargetResolver.resolve_plan(entity, spell, selection, requirements.units,
          triggered?: true,
          locations: requirements.locations
        )

      triggered_cast(entity, effect, spell, plan, selection, requirements.objects)
    else
      {:error, reason} ->
        [Effects.spell_cast_failed(spell, reason)]
    end
  end

  defp resolve_area_trigger(entity, effect, spell) do
    selection = Target.unit(effect.target_guid)
    targets = SpellTargetResolver.resolve_plan(entity, spell, selection, %UnitTargets{}, triggered?: true)

    triggered_cast(entity, effect, spell, targets, selection)
  end

  defp triggered_cast(entity, effect, spell, targets, selection) do
    objects = SpellObjects.resolve(entity, spell, selection, SpellFocus.find(entity, spell))

    case ObjectTargets.validate(spell, objects) do
      :ok -> triggered_cast(entity, effect, spell, targets, selection, objects)
      {:error, reason} -> [Effects.spell_cast_failed(spell, reason)]
    end
  end

  defp triggered_cast(entity, effect, spell, targets, selection, objects) do
    units = if is_struct(targets, UnitTargets), do: targets
    targets = if units, do: UnitTargets.guids(units), else: targets
    targets = if effect.requires_living_target?, do: Enum.filter(targets, &living_target?(entity, &1)), else: targets

    if effect.requires_living_target? and targets == [],
      do: [],
      else: triggered_effects(entity, effect, spell, targets, selection, objects, units)
  end

  defp triggered_effects(entity, effect, spell, targets, selection, objects, units) do
    targets =
      if ObjectTargets.required?(spell) and Enum.all?(spell.effects, &(&1.type == :activate_object)),
        do: [],
        else: targets

    contexts =
      Enum.map(targets, fn target_guid ->
        entity
        |> trigger_context(%{effect | target_guid: target_guid}, spell)
        |> trigger_outcome(spell, target_guid)
      end)

    {hits, misses} = Enum.split_with(contexts, &(&1.hit_outcome == :hit))
    hit_guids = Enum.map(hits, & &1.target_guid)
    chain = Chain.plan(entity, spell, targets, hit_guids)
    target_counts = UnitTargets.counts(units)
    misses = Enum.map(misses, &%{guid: &1.target_guid, reason: 2})

    launch =
      Effects.spell_go(
        effect.source_guid || entity.object.guid,
        effect.spell_id,
        Enum.uniq(hit_guids ++ ObjectTargets.guids(objects)),
        selection,
        effect.cast_item_guid,
        misses
      )

    deliveries =
      Enum.flat_map(contexts, fn context ->
        context = %{
          Chain.put_context(context, chain)
          | effect_indices: UnitTargets.indices(units, context.target_guid),
            effect_target_counts: target_counts,
            destination_position: Target.ground_location(selection),
            selected_target_guid: Target.unit_guid(selection)
        }

        resolved_delivery(entity, Effects.deliver_spell(context.target_guid, context, spell))
      end)

    actions = Enum.flat_map(ObjectTargets.actions(spell, objects), &resolve(entity, &1))
    context = trigger_context(entity, effect, spell)

    completion = %Effects.SpellCastCompleted{
      source_guid: context.caster_guid,
      target_guid: context.target_guid,
      spell: spell,
      proc_origin: ProcOrigin.classify(spell, context)
    }

    movement =
      if is_integer(Target.unit_guid(selection)) and Enum.any?(spell.effects, &(&1.type == :charge)),
        do:
          Movement.resolve(
            entity,
            Effects.charge(Target.unit_guid(selection), attack_on_arrival?: Charge.attack_on_arrival?(spell))
          ),
        else: []

    launch_combat =
      SpellLaunch.resolve(entity, %Effects.SpellLaunched{
        source_guid: context.caster_guid,
        target_guid: Target.unit_guid(selection),
        spell: spell,
        effect_indices: UnitTargets.indices(units, Target.unit_guid(selection))
      })

    events = triggered_send_events(entity, spell, objects, selection, context.caster_guid || entity.object.guid)

    [launch | launch_combat ++ movement ++ deliveries ++ actions ++ events ++ [completion]]
  end

  defp triggered_send_events(entity, spell, objects, selection, caster_guid) do
    if SendEvent.cast_level?(spell) do
      focus_guid = with %Focus{guid: guid} <- SpellFocus.find(entity, spell), do: guid
      target_guid = SendEvent.target(focus_guid, ObjectTargets.guids(objects), Target.unit_guid(selection), caster_guid)
      SendEvent.cast_events(spell, entity.object.guid, caster_guid, target_guid)
    else
      []
    end
  end

  defp living_target?(%{object: %{guid: guid}, unit: %Unit{health: health}}, guid),
    do: is_integer(health) and health > 0

  defp living_target?(_entity, guid), do: match?(%{alive?: true}, Metadata.query(guid, [:alive?]))

  defp trigger_outcome(%CastContext{caster_guid: guid} = context, _spell, guid), do: context

  defp trigger_outcome(context, %Spell{dmg_class: 1} = spell, target_guid) do
    if Spell.harmful?(spell) do
      target =
        Metadata.query(target_guid, [
          :alive?,
          :level,
          :attacker_spell_hit_chance,
          :aoe_avoidance,
          :mechanic_resistance,
          :school_resistances,
          :no_spell_defense?
        ]) || %{}

      hit? = SpellResist.context_hit?(context, spell, target, Guid.entity_type(target_guid) == :player)
      %{context | hit_outcome: if(hit?, do: :hit, else: :resist)}
    else
      context
    end
  end

  defp trigger_outcome(context, _spell, _target_guid), do: context

  defp projectile_delay_ms(entity, %Effects.DeliverSpell{spell: spell, cast_context: context, target_guid: target}) do
    SpellLaunch.delay(entity, context.caster_guid, target, spell)
  end

  defp scripted_proc_spell(%Spell{} = spell, %Effects.TriggerSpell{triggering_spell_id: triggering_spell_id}) do
    case Scripts.proc_trigger_spell_id(spell, triggering_spell_id) do
      spell_id when spell_id == spell.id -> spell
      spell_id when is_integer(spell_id) -> SpellLoader.load(spell_id)
      _missing -> nil
    end
  end

  defp apply_trigger_override(%Spell{} = spell, %Effects.TriggerSpell{} = effect) do
    spell
    |> apply_trigger_effect_override(effect)
    |> apply_trigger_duration_override(effect)
  end

  defp apply_trigger_override(nil, _effect), do: nil

  defp apply_trigger_effect_override(%Spell{effects: effects} = spell, %Effects.TriggerSpell{} = trigger) do
    points = custom_effect_points(trigger)

    effects =
      Enum.map(effects, fn %Spell.Effect{} = effect ->
        case Map.get(points, effect.index) do
          amount when is_integer(amount) -> %{effect | base_points: amount, die_sides: 0, base_dice: 0}
          _missing -> effect
        end
      end)

    %{spell | effects: effects}
  end

  defp custom_effect_points(%Effects.TriggerSpell{slot: index, amount: amount, effect_base_points: points})
       when is_integer(index) and is_integer(amount), do: Map.put(points, index, amount)

  defp custom_effect_points(%Effects.TriggerSpell{effect_base_points: points}), do: points

  defp apply_trigger_duration_override(%Spell{} = spell, %Effects.TriggerSpell{duration_ms: duration_ms})
       when is_integer(duration_ms) and (duration_ms > 0 or duration_ms == -1) do
    %{spell | duration_ms: duration_ms, max_duration_ms: duration_ms}
  end

  defp apply_trigger_duration_override(spell, _effect), do: spell

  defp triggered_target(_entity, %Effects.TriggerSpell{target_role: role, target_guid: guid}, _spell)
       when role in [:caster, :other, :pet], do: guid

  defp triggered_target(%{object: %{guid: guid}} = entity, %Effects.TriggerSpell{source_guid: guid} = effect, spell) do
    SpellTarget.redirect_trigger_target(entity, effect.target_guid, spell)
  end

  defp triggered_target(_entity, %Effects.TriggerSpell{} = effect, _spell), do: effect.target_guid

  defp trigger_context(%{object: %{guid: guid}} = entity, %Effects.TriggerSpell{source_guid: guid} = effect, spell) do
    %{
      CastContext.from_caster(entity, spell, effect.target_guid)
      | target_hostile?: Spell.requires_hostile_target?(spell),
        deep_wounds_tick: Warrior.deep_wounds_tick(entity, spell, Time.now(), effect.attack_hand),
        triggered?: true,
        cast_item_guid: effect.cast_item_guid,
        extra_attack?: effect.extra_attack?,
        triggered_by_aura?: is_integer(effect.triggering_spell_id),
        required_aura_source: required_aura_source(entity, effect, spell),
        triggered_by_proc?: triggered_by_proc?(effect),
        target_role: effect.target_role
    }
  end

  defp trigger_context(entity, %Effects.TriggerSpell{} = effect, spell) do
    %CastContext{
      caster_guid: effect.source_guid,
      triggered?: true,
      cast_item_guid: effect.cast_item_guid,
      extra_attack?: effect.extra_attack?,
      triggered_by_aura?: is_integer(effect.triggering_spell_id),
      required_aura_source: required_aura_source(entity, effect, spell),
      triggered_by_proc?: triggered_by_proc?(effect),
      caster_level: effect.source_level || 1,
      target_guid: effect.target_guid,
      target_role: effect.target_role,
      target_hostile?: Spell.requires_hostile_target?(spell),
      spell: spell
    }
    |> inherit_hit_context(effect.hit_context, spell)
  end

  defp required_aura_source(
         %{object: %{guid: guid}} = entity,
         %Effects.TriggerSpell{target_guid: guid, triggering_spell_id: id},
         %Spell{duration_ms: -1} = spell
       )
       when is_integer(id) do
    TriggeredLifetime.source(entity, trigger_spell(entity, id), spell)
  end

  defp required_aura_source(_entity, _effect, _spell), do: nil

  defp inherit_hit_context(%CastContext{caster_guid: guid} = context, %CastContext{caster_guid: guid} = source, spell) do
    bonus =
      if source.spell_hit_snapshot,
        do: SpellResist.hit_bonus(source.spell_hit_snapshot, spell),
        else: source.spell_hit_bonus

    %{
      context
      | caster_level: source.caster_level || context.caster_level,
        spell_hit_bonus: bonus,
        spell_hit_snapshot: source.spell_hit_snapshot,
        resistance_penetration: source.resistance_penetration
    }
  end

  defp inherit_hit_context(context, _source, _spell), do: context

  defp triggered_by_proc?(%Effects.TriggerSpell{triggering_spell_id: id}) when is_integer(id) do
    case SpellLoader.cached(id) do
      %Spell{proc_type_mask: mask} when is_integer(mask) -> mask != 0
      _ -> false
    end
  end

  defp triggered_by_proc?(_effect), do: false
end
