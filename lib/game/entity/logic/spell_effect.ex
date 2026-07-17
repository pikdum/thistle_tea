defmodule ThistleTea.Game.Entity.Logic.SpellEffect do
  @moduledoc """
  Applies a cast spell's effects (damage, healing, auras, item creation, …) to
  a target entity, returning the updated entity and the events to emit.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Paladin
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Entity.Logic.Warlock
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Scripts

  @schools [:physical, :holy, :fire, :nature, :frost, :shadow, :arcane]

  @resurrect_effects [:resurrect, :resurrect_new]

  def receive(target, %CastContext{} = context, %Spell{} = spell, now) when is_integer(now) do
    if immune_to_harmful_spell?(target, context, spell) do
      {target, [Event.spell_log_miss(context.caster_guid, target.object.guid, spell.id, :immune)]}
    else
      effects = applicable_effects(target, context, spell.effects)
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

  defp immune_to_harmful_spell?(target, %CastContext{caster_guid: caster_guid}, %Spell{} = spell) do
    target.object.guid != caster_guid and Spell.harmful?(spell) and Aura.school_immune?(target, spell.school)
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

  defp caster_target_effect?(%Effect{type: type} = effect) when type in [:apply_aura, :instakill] do
    effect.implicit_target_a == :caster or effect.implicit_target_b == :caster
  end

  defp caster_target_effect?(_effect), do: false

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
    Spell.melee_ability?(spell) and target_guid != caster_guid
  end

  defp receive_melee_ability(target, %CastContext{} = context, spell, now) do
    result = AttackTable.roll_special(target, special_attack(context, spell))

    case result.outcome do
      outcome when outcome in [:miss, :dodge, :parry, :block] ->
        target = maybe_mark_defense(target, outcome, now)
        {target, melee_avoid_events(target, context, spell, outcome)}

      _hit ->
        context = %{context | melee_crit?: result.crit?}

        {target, events} = apply_effects(target, context, spell.effects, [], now)

        events =
          if rogue_feedback_spell?(spell) do
            events ++
              [
                Event.attack_outcome(
                  context.caster_guid,
                  target.object.guid,
                  result.outcome,
                  dealt_damage(events),
                  spell.id
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

      match?(%Effect{type: type} when type in [:apply_aura, :apply_area_aura], effect) and aura_applied? ->
        {target, events, aura_applied?}

      match?(%Effect{type: type} when type in [:apply_aura, :apply_area_aura], effect) ->
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
    result =
      cond do
        Warlock.conflagrate?(spell) and not Warlock.has_immolate_from?(state, context.caster_guid) ->
          {state, []}

        Spell.melee_ability?(spell) ->
          melee_ability_damage(state, context, spell, school_damage_roll(context, spell, effect), now)

        true ->
          apply_damage_effect(state, context, spell, effect, now)
      end

    consume_conflagrate_immolate(result, context, spell, now)
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :health_leech} = effect, now) do
    {state, events} = apply_damage_effect(state, context, spell, effect, now)
    damage = dealt_damage(events)
    {state, events ++ if(damage > 0, do: [Event.heal_entity(context.caster_guid, damage)], else: [])}
  end

  defp apply_effect(state, %CastContext{} = context, %Spell{name: "Demonic Sacrifice"}, %Effect{type: :instakill}, now) do
    events =
      case Warlock.sacrifice_event(state, context) do
        nil -> []
        event -> [event]
      end

    {Core.take_damage(state, state.unit.health || 0, now, source: context.caster_guid), events}
  end

  defp apply_effect(state, %CastContext{} = context, _spell, %Effect{type: :instakill}, now) do
    {Core.take_damage(state, state.unit.health || 0, now, source: context.caster_guid), []}
  end

  defp apply_effect(state, %CastContext{}, _spell, %Effect{type: :add_combo_points}, _now), do: {state, []}

  defp apply_effect(
         state,
         %CastContext{caster_guid: caster_guid},
         %Spell{id: spell_id},
         %Effect{type: :summon_pet, misc_value: entry},
         _now
       )
       when state.object.guid == caster_guid and is_integer(entry) and entry > 0 do
    {state, [Event.summon_pet(caster_guid, entry, spell_id)]}
  end

  defp apply_effect(
         %Character{internal: %{active_pet_entry: entry}} = state,
         %CastContext{caster_guid: caster_guid},
         %Spell{id: spell_id},
         %Effect{type: type, misc_value: 0},
         _now
       )
       when type in [:summon_pet, :revive_pet] and is_integer(entry) and entry > 0 do
    {state, [Event.summon_pet(caster_guid, entry, spell_id)]}
  end

  defp apply_effect(
         %Character{} = state,
         %CastContext{caster_guid: caster_guid},
         _spell,
         %Effect{type: :dismiss_pet},
         _now
       ) do
    {state, [Event.dismiss_pet(caster_guid)]}
  end

  defp apply_effect(state, %CastContext{}, spell, %Effect{type: :summon_game_object, misc_value: entry}, _now)
       when is_integer(entry) and entry > 0 do
    {state, [Event.summon_game_object(entry, max(spell.duration_ms || 0, 0))]}
  end

  defp apply_effect(
         %{object: %{entry: entry}} = state,
         %CastContext{caster_guid: owner_guid},
         _spell,
         %Effect{type: :tame_creature},
         _now
       )
       when is_integer(entry) and entry > 0 do
    {state, [Event.tame_creature(owner_guid, entry)]}
  end

  defp apply_effect(%Character{} = state, %CastContext{}, spell, %Effect{type: :clear_threat}, now) do
    {state, mob_guids} = PlayerCombat.vanish(state, now)

    events =
      [Event.drop_nearby_threat()] ++
        Enum.map(mob_guids, &Event.drop_threat/1) ++
        vanish_attack_stop_events(state) ++ maybe_vanish_stealth_events(state, spell)

    {state, events}
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: type} = effect, now)
       when type in [:weapon_damage, :weapon_damage_noschool, :normalized_weapon_damage, :weapon_percent_damage] do
    melee_ability_damage(state, context, spell, weapon_ability_damage(context, effect), now)
  end

  defp apply_effect(state, %CastContext{} = context, _spell, %Effect{type: :attack_me}, _now) do
    {Threat.taunt(state, context.caster_guid), []}
  end

  defp apply_effect(state, %CastContext{} = context, _spell, %Effect{type: :modify_threat} = effect, _now) do
    {Threat.modify(state, context.caster_guid, Effect.damage_roll(effect)), []}
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :heal} = effect, _now) do
    healing =
      Effect.damage_roll(effect) + bonus_amount(context.healing_bonus, spell) +
        Aura.flat_modifier(state, :mod_healing, Spell.school_mask(spell)) +
        Paladin.blessing_of_light_bonus(state, spell)

    healing = max(trunc(healing * healing_taken_multiplier(state, spell)), 0)
    events = Threat.heal_threat_events(state, context.caster_guid, healing)

    {Core.heal(state, healing), events}
  end

  defp apply_effect(state, %CastContext{} = context, _spell, %Effect{type: :heal_max_health}, _now) do
    healing = max((state.unit.max_health || 0) - (state.unit.health || 0), 0)
    events = Threat.heal_threat_events(state, context.caster_guid, healing)
    {Core.heal(state, healing), events}
  end

  defp apply_effect(state, %CastContext{}, _spell, %Effect{type: :persistent_area_aura}, _now) do
    {state, []}
  end

  defp apply_effect(
         state,
         %CastContext{} = context,
         spell,
         %Effect{type: :trigger_spell, trigger_spell_id: spell_id},
         _now
       )
       when is_integer(spell_id) and spell_id > 0 do
    if Scripts.dummy_effect(spell) == :execute do
      {state, []}
    else
      event = Event.trigger_spell(context.caster_guid, context.caster_level, state.object.guid, spell_id)
      {state, [event]}
    end
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :dummy} = effect, now) do
    case Scripts.dummy_effect(spell) do
      :life_tap ->
        Warlock.life_tap(state, context, spell, effect, now)

      :soul_link ->
        event =
          Event.trigger_spell(state.object.guid, state.unit.level || 1, context.caster_guid, 25_228,
            target_role: :caster
          )

        {state, [event]}

      dummy_effect ->
        apply_class_dummy(state, context, spell, effect, dummy_effect, now)
    end
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

  defp apply_effect(
         state,
         %CastContext{caster_guid: caster_guid},
         _spell,
         %Effect{type: :energize, misc_value: power_type} = effect,
         _now
       )
       when is_integer(power_type) and power_type >= 0 do
    if effect.implicit_target_a == :caster and state.object.guid != caster_guid do
      {state, [Event.grant_power(caster_guid, power_type, Effect.damage_roll(effect))]}
    else
      {Resources.gain_power(state, power_type, Effect.damage_roll(effect)), []}
    end
  end

  defp apply_effect(state, %CastContext{}, _spell, %Effect{type: :create_item, misc_value: item_id} = effect, _now)
       when is_integer(item_id) and item_id > 0 do
    count = max(Effect.damage_roll(effect), 1)
    {state, [Event.create_item(item_id, count)]}
  end

  defp apply_effect(state, %CastContext{}, spell, %Effect{type: :script_effect}, _now) do
    case Warlock.healthstone_item(state, spell) do
      item_id when is_integer(item_id) and item_id > 0 -> {state, [Event.create_item(item_id, 1)]}
      _ -> {state, []}
    end
  end

  defp apply_effect(state, %CastContext{caster_guid: caster_guid}, _spell, %Effect{type: :power_drain} = effect, _now) do
    available = max(state.unit.power1 || 0, 0)
    drained = min(Effect.damage_roll(effect), available)
    unit = %{state.unit | power1: available - drained}
    {%{state | unit: unit}, [Event.grant_power(caster_guid, 0, drained)]}
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

  defp apply_class_dummy(state, context, spell, effect, dummy_effect, now) do
    case dummy_effect do
      :execute ->
        apply_execute(state, context, spell, effect, now)

      :last_stand ->
        event =
          Event.trigger_spell(
            context.caster_guid,
            context.caster_level,
            state.object.guid,
            Scripts.last_stand_health_buff_id()
          )

        {state, [event]}

      :preparation ->
        {Cooldowns.reset(state, [14_177, {:category, 39}, {:category, 44}, {:category, 66}]), []}

      {:holy_shock, spell_ids} ->
        spell_id = if context.target_hostile?, do: spell_ids.damage, else: spell_ids.heal
        {state, [Event.trigger_spell(context.caster_guid, context.caster_level, state.object.guid, spell_id)]}

      :judgement_of_command ->
        spell_id = Effect.damage_roll(effect)

        if spell_id > 1 do
          {state, [Event.trigger_spell(context.caster_guid, context.caster_level, state.object.guid, spell_id)]}
        else
          {state, []}
        end

      _unscripted ->
        {state, []}
    end
  end

  defp maybe_vanish_stealth_events(state, %Spell{name: "Vanish"}), do: vanish_stealth_events(state)
  defp maybe_vanish_stealth_events(_state, _spell), do: []

  defp vanish_stealth_events(%{object: %{guid: guid}, unit: %{level: level}, internal: %{spellbook: spellbook}})
       when is_map(spellbook) do
    spell_id =
      spellbook
      |> Map.values()
      |> Enum.filter(&match?(%Spell{name: "Stealth"}, &1))
      |> Enum.max_by(&(&1.rank || 0), fn -> nil end)
      |> case do
        %Spell{id: id} -> id
        _ -> nil
      end

    if is_integer(spell_id), do: [Event.trigger_spell(guid, level || 1, guid, spell_id)], else: []
  end

  defp vanish_stealth_events(_state), do: []

  defp vanish_attack_stop_events(%{object: %{guid: guid}, unit: %{target: target}})
       when is_integer(target) and target > 0 do
    [Event.attack_stop(guid, target)]
  end

  defp vanish_attack_stop_events(_state), do: []

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
    base = effect_amount(spell, effect, context.combo_points)
    rolled = base + damage_bonus(context, spell, opts)
    rolled = trunc(rolled * (context.damage_done_multiplier || 1.0) * scripted_damage_multiplier(state, spell))

    damage = max(rolled + Aura.flat_modifier(state, :mod_damage_taken, Spell.school_mask(spell)), 0)

    school = school_atom(spell)
    resisted = school_resisted_amount(state, damage, school, context.caster_level, opts)
    damage = damage - resisted

    {state, absorbed} =
      Core.take_damage_with_absorb(state, damage, now,
        school: school,
        source: context.caster_guid,
        threat_multiplier: damage_threat_multiplier(context)
      )

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

  defp scripted_damage_multiplier(state, %Spell{name: "Judgement of Command"}) do
    if Aura.has_aura?(state, :mod_stun), do: 1.0, else: 0.5
  end

  defp scripted_damage_multiplier(_state, _spell), do: 1.0

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

  defp school_damage_roll(%CastContext{} = context, spell, %Effect{} = effect) do
    roll = effect_amount(spell, effect, context.combo_points) + eviscerate_attack_power(spell, context)

    if Scripts.ap_percent_damage?(spell) do
      trunc(roll * (context.attack_power || 0) / 100)
    else
      roll
    end
  end

  defp effect_amount(%Spell{} = spell, %Effect{} = effect, points) do
    if Scripts.finisher?(spell), do: Effect.amount(effect, points || 0), else: Effect.damage_roll(effect)
  end

  defp eviscerate_attack_power(%Spell{name: "Eviscerate"}, %CastContext{} = context) do
    trunc((context.attack_power || 0) * (context.combo_points || 0) * 0.03)
  end

  defp eviscerate_attack_power(_spell, _context), do: 0

  defp weapon_ability_damage(%CastContext{} = context, %Effect{type: :normalized_weapon_damage} = effect) do
    normalized_weapon_roll(context) + Effect.damage_roll(effect)
  end

  defp weapon_ability_damage(%CastContext{} = context, %Effect{type: :weapon_percent_damage} = effect) do
    trunc(weapon_roll(context) * Effect.damage_roll(effect) / 100)
  end

  defp weapon_ability_damage(%CastContext{} = context, %Effect{} = effect) do
    weapon_roll(context) + Effect.damage_roll(effect)
  end

  defp weapon_roll(%CastContext{attack_time_ms: attack_time_ms} = context)
       when is_number(attack_time_ms) and attack_time_ms > 0 do
    weapon_base_roll(context) + attack_power_bonus(context, attack_time_ms / 1000)
  end

  defp weapon_roll(%CastContext{} = context), do: weapon_base_roll(context)

  defp normalized_weapon_roll(%CastContext{normalized_speed: speed} = context) when is_number(speed) and speed > 0 do
    weapon_base_roll(context) + attack_power_bonus(context, speed)
  end

  defp normalized_weapon_roll(%CastContext{} = context), do: weapon_roll(context)

  defp weapon_base_roll(%CastContext{weapon_base_min: min, weapon_base_max: max})
       when is_number(min) and is_number(max) do
    Math.random_int(trunc(min), max(trunc(max), trunc(min)))
  end

  defp weapon_base_roll(_context), do: 0

  defp attack_power_bonus(%CastContext{attack_power: attack_power}, speed_seconds)
       when is_integer(attack_power) and attack_power > 0 do
    trunc(attack_power / 14 * speed_seconds)
  end

  defp attack_power_bonus(_context, _speed_seconds), do: 0

  defp maybe_mark_defense(state, outcome, now) when outcome in [:dodge, :parry, :block] do
    Reactive.mark_defense(state, now)
  end

  defp maybe_mark_defense(state, _outcome, _now), do: state

  defp apply_execute(state, %CastContext{} = context, spell, %Effect{} = effect, now) do
    rage = context.caster_power || 0
    damage = Effect.damage_roll(effect) + trunc(rage * effect.damage_multiplier)
    damage_spell = %{spell | id: Scripts.execute_damage_spell_id()}

    {state, events} = melee_ability_damage(state, context, damage_spell, damage, now)

    {state, events ++ [Event.drain_rage(context.caster_guid)]}
  end

  defp melee_ability_damage(state, %CastContext{} = context, spell, damage, now) do
    school = school_atom(spell)
    damage = trunc(damage * (context.damage_done_multiplier || 1.0))

    damage =
      max(damage + Aura.flat_modifier(state, :mod_damage_taken, Spell.school_mask(spell)), 0)

    damage = mitigate_physical(state, context, school, damage)
    damage = if context.melee_crit?, do: damage * 2, else: damage

    {state, absorbed} =
      Core.take_damage_with_absorb(state, damage, now,
        school: school,
        source: context.caster_guid,
        threat_multiplier: damage_threat_multiplier(context)
      )

    event =
      Event.spell_damage(context.caster_guid, state.object.guid, spell, damage,
        absorbed: absorbed,
        crit?: context.melee_crit? || false
      )

    {state, [event]}
  end

  defp mitigate_physical(%{unit: %{normal_resistance: armor}}, %CastContext{} = context, :physical, damage)
       when damage > 0 do
    AttackTable.armor_reduced_damage(damage, armor || 0, context.caster_level)
  end

  defp mitigate_physical(_state, _context, _school, damage), do: damage

  defp damage_threat_multiplier(%CastContext{} = context) do
    base = context.threat_multiplier || 1.0

    case context.spell_threat do
      %{multiplier: multiplier} when is_number(multiplier) -> base * multiplier
      _no_entry -> base
    end
  end

  defp melee_avoid_events(%{object: %{guid: target_guid}}, %CastContext{} = context, spell, outcome) do
    [
      Event.spell_log_miss(context.caster_guid, target_guid, spell.id, outcome),
      Event.attack_outcome(context.caster_guid, target_guid, outcome, 0, spell.id)
    ]
  end

  defp dealt_damage(events) do
    Enum.reduce(events, 0, fn
      %Event{type: :spell_damage, damage: damage}, acc when is_integer(damage) -> acc + damage
      _event, acc -> acc
    end)
  end

  defp rogue_feedback_spell?(%Spell{} = spell) do
    Scripts.finisher?(spell) or spell.name == "Gouge" or
      Enum.any?(spell.effects, &match?(%Effect{type: :add_combo_points}, &1))
  end

  defp special_attack(%CastContext{} = context, spell) do
    %{
      caster: context.caster_guid,
      caster_level: context.caster_level,
      caster_player?: context.caster_type == :player,
      caster_attack_skill: context.attack_skill,
      crit_chance: context.melee_crit_chance,
      caster_position: attack_position(context.caster_position),
      spell_school_mask: Spell.school_mask(spell),
      block_allowed?: Spell.attribute?(spell, :completely_blocked)
    }
  end

  defp attack_position({_map, x, y, z}), do: {x, y, z}
  defp attack_position(_position), do: nil

  defp consume_conflagrate_immolate({state, events}, %CastContext{caster_guid: caster_guid}, spell, now) do
    if Warlock.conflagrate?(spell) do
      {state, aura_events} = Warlock.consume_immolate(state, caster_guid, now)
      {state, events ++ aura_events}
    else
      {state, events}
    end
  end
end
