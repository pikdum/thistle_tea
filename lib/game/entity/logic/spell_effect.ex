defmodule ThistleTea.Game.Entity.Logic.SpellEffect do
  @moduledoc """
  Applies a cast spell's effects (damage, healing, auras, item creation, …) to
  a target entity, returning the updated entity and the events to emit.
  """
  import Bitwise, only: [<<<: 2]

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat, as: BTCombat
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Druid
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Hunter
  alias ThistleTea.Game.Entity.Logic.Mage
  alias ThistleTea.Game.Entity.Logic.Paladin
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.Rogue
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Entity.Logic.Warlock
  alias ThistleTea.Game.Entity.Logic.Warrior
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Coefficient
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Scripts

  @schools [:physical, :holy, :fire, :nature, :frost, :shadow, :arcane]

  @resurrect_effects [:resurrect, :resurrect_new]

  @weapon_effect_types [:weapon_damage, :weapon_damage_noschool, :normalized_weapon_damage, :weapon_percent_damage]

  def receive(target, %CastContext{} = context, %Spell{} = spell, now) when is_integer(now) do
    if immune_to_harmful_spell?(target, context, spell) do
      {target, [Event.spell_log_miss(context.caster_guid, target.object.guid, spell.id, :immune)]}
    else
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
          Event.trigger_spell(context.caster_guid, context.caster_level, target.object.guid, effect.trigger_spell_id)

        {target, events ++ [event], applied}

      aura_effect?(effect) ->
        if MapSet.member?(applied, :aura) do
          {target, events, applied}
        else
          {target, aura_events} = apply_auras(target, context, now)
          {target, events ++ aura_events, MapSet.put(applied, :aura)}
        end

      weapon_effect?(effect) ->
        if MapSet.member?(applied, :weapon) do
          {target, events, applied}
        else
          {target, weapon_events} = apply_weapon_group(target, context, context.spell, now)
          {target, events ++ weapon_events, MapSet.put(applied, :weapon)}
        end

      true ->
        {target, effect_events} = apply_effect(target, context, context.spell, effect, now)
        {target, events ++ effect_events, applied}
    end
  end

  defp aura_effect?(%Effect{type: type}), do: type in [:apply_aura, :apply_area_aura]

  defp weapon_effect?(%Effect{type: type}), do: type in @weapon_effect_types

  defp apply_weapon_group(state, %CastContext{} = context, spell, now) do
    effects = Enum.filter(context.spell.effects, &weapon_effect?/1)
    context = apply_target_attack_power_bonus(state, context, spell)

    base =
      if Enum.any?(effects, &(&1.type == :normalized_weapon_damage)),
        do: normalized_weapon_roll(context),
        else: weapon_roll(context)

    flat =
      effects
      |> Enum.reject(&(&1.type == :weapon_percent_damage))
      |> Enum.map(&rolled_amount(spell, &1, context))
      |> Enum.sum()

    percent =
      effects
      |> Enum.filter(&(&1.type == :weapon_percent_damage))
      |> Enum.reduce(1.0, fn effect, acc -> acc * rolled_amount(spell, effect, context) / 100 end)

    melee_ability_damage(state, context, spell, trunc((base + flat) * percent), now)
  end

  defp apply_auras(target, context, now) do
    {target, events} = Aura.apply_spell(target, context, context.spell, now)
    {target, class_events} = Hunter.after_aura(target, context.spell, now)
    {target, events ++ script_trigger_events(target, context) ++ class_events}
  end

  defp script_trigger_events(target, %CastContext{spell: spell} = context) do
    with trigger_id when is_integer(trigger_id) <- Scripts.apply_trigger(spell),
         true <- Aura.has_spell?(target, spell.id) do
      [Event.trigger_spell(context.caster_guid, context.caster_level, target.object.guid, trigger_id)]
    else
      _ -> []
    end
  end

  defp channel_ticked_trigger?(spell, %Effect{} = effect), do: Spell.channel_ticked_effect?(spell, effect)
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

    result
    |> consume_conflagrate_immolate(context, spell, now)
    |> consume_ferocious_bite_energy(context, spell)
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :health_leech} = effect, now) do
    health_before = max(state.unit.health || 0, 0)
    {state, events} = apply_damage_effect(state, context, spell, effect, now)
    damage = min(dealt_damage(events), health_before)
    healed = trunc(damage * leech_multiplier(effect))
    {state, events ++ if(healed > 0, do: [Event.heal_entity(context.caster_guid, healed)], else: [])}
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :instakill}, now) do
    events =
      if Warlock.demonic_sacrifice?(spell) do
        case Warlock.sacrifice_event(state, context) do
          nil -> []
          event -> [event]
        end
      else
        []
      end

    {Core.take_damage(state, state.unit.health || 0, now, source: context.caster_guid), events}
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
         state,
         %CastContext{
           caster_guid: summoner_guid,
           selected_target_guid: target_guid,
           caster_zone: zone_id,
           caster_position: {_world, _x, _y, _z} = position
         },
         _spell,
         %Effect{type: :summon_player},
         _now
       )
       when is_integer(target_guid) do
    {state, [Event.summon_request(summoner_guid, target_guid, zone_id, position)]}
  end

  defp apply_effect(
         state,
         %CastContext{
           caster_guid: owner_guid,
           caster_position: {_world, caster_x, caster_y, caster_z},
           caster_orientation: orientation,
           destination_position: destination
         },
         spell,
         %Effect{type: :summon_demon, misc_value: entry} = effect,
         _now
       )
       when is_integer(entry) and entry > 0 do
    orientation = orientation || 0.0
    {x, y, z} = summon_effect_position(effect, destination, {caster_x, caster_y, caster_z}, orientation)

    summon = %{
      entry: entry,
      owner_guid: owner_guid,
      position: {x, y, z, orientation},
      despawn_delay_ms: summon_duration(spell),
      despawn_type: 1,
      run?: false,
      unique?: false,
      attack_target: nil,
      script_id: 0,
      post_spawn_spells: Warlock.summon_spells(spell)
    }

    {state, [Event.summon_creature(summon, [], nil)]}
  end

  defp apply_effect(
         state,
         %CastContext{
           caster_guid: owner_guid,
           caster_position: {_world, caster_x, caster_y, caster_z},
           caster_orientation: orientation,
           destination_position: destination
         },
         %Spell{id: spell_id} = spell,
         %Effect{type: :summon_possessed, misc_value: entry} = effect,
         _now
       )
       when is_integer(entry) and entry > 0 do
    orientation = orientation || 0.0
    {x, y, z} = summon_effect_position(effect, destination, {caster_x, caster_y, caster_z}, orientation)

    summon = %{
      entry: entry,
      owner_guid: owner_guid,
      position: {x, y, z, orientation},
      despawn_delay_ms: summon_duration(spell),
      despawn_type: 1,
      run?: false,
      unique?: true,
      attack_target: nil,
      script_id: 0,
      post_spawn_spells: [],
      control: :possessed,
      control_spell_id: spell_id
    }

    {state, [Event.summon_creature(summon, [], nil)]}
  end

  defp apply_effect(
         state,
         %CastContext{},
         spell,
         %Effect{type: :summon_totem, summon_slot: slot, misc_value: entry},
         _now
       )
       when slot in 1..4 and is_integer(entry) and entry > 0 do
    {state, [Event.summon_totem(entry, slot, max(spell.duration_ms || 0, 0))]}
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
    {state, aura_events} = remove_vanish_stalked(state, spell, now)
    {state, mob_guids} = PlayerCombat.vanish(state, now)

    events =
      aura_events ++
        [Event.drop_nearby_threat()] ++
        Enum.map(mob_guids, &Event.drop_threat/1) ++
        vanish_attack_stop_events(state) ++ maybe_vanish_stealth_events(state, spell)

    {state, events}
  end

  defp apply_effect(state, %CastContext{} = context, _spell, %Effect{type: :attack_me}, _now) do
    {Threat.taunt(state, context.caster_guid), []}
  end

  defp apply_effect(
         %{unit: %{target: target}} = state,
         %CastContext{} = context,
         spell,
         %Effect{type: :add_extra_attacks} = effect,
         _now
       )
       when is_integer(target) and target > 0 do
    count = max(rolled_amount(spell, effect, context), 1)
    {BTCombat.extra_attacks(state, target, count), []}
  end

  defp apply_effect(state, %CastContext{}, _spell, %Effect{type: :add_extra_attacks}, _now), do: {state, []}

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :modify_threat} = effect, _now) do
    {Threat.change(state, context.caster_guid, rolled_amount(spell, effect, context)), []}
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :heal} = effect, now) do
    {state, swiftmend_healing, swiftmend_events} = Druid.consume_swiftmend_hot(state, spell, now)

    base_healing =
      trunc((rolled_amount(spell, effect, context) + swiftmend_healing) * (context.effect_healing_multiplier || 1.0))

    healing =
      base_healing + Coefficient.bonus(context.healing_bonus || 0, spell, effect, :direct) +
        Aura.flat_modifier(state, :mod_healing, Spell.school_mask(spell)) +
        Paladin.blessing_of_light_bonus(state, spell)

    healing = max(trunc(healing * healing_taken_multiplier(state, spell)), 0)
    crit? = heal_crit?(context, spell)
    healing = if crit?, do: healing + div(healing, 2), else: healing
    events = Threat.heal_threat_events(state, context.caster_guid, healing)
    heal_event = Event.spell_heal(context.caster_guid, state.object.guid, spell, healing, crit?)

    {Core.heal(state, healing), swiftmend_events ++ events ++ [heal_event]}
  end

  defp apply_effect(state, %CastContext{} = context, _spell, %Effect{type: :heal_max_health}, _now) do
    healing = max(context.caster_max_health || state.unit.max_health || 0, 0)
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
         %Effect{type: :trigger_spell, trigger_spell_id: spell_id} = effect,
         _now
       )
       when is_integer(spell_id) and spell_id > 0 do
    if Scripts.dummy_effect(spell) == :execute do
      {state, []}
    else
      target_guid = trigger_target_guid(state, context, effect)
      event = Event.trigger_spell(context.caster_guid, context.caster_level, target_guid, spell_id)
      {state, [event]}
    end
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :dummy} = effect, now) do
    case vmangos_script_events(state, context, spell) do
      [] ->
        case Scripts.dummy_effect(spell) do
          :life_tap -> Warlock.life_tap(state, context, spell, effect, now)
          dummy_effect -> apply_class_dummy(state, context, spell, effect, dummy_effect, now)
        end

      events ->
        {state, events}
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
         %CastContext{caster_guid: caster_guid} = context,
         spell,
         %Effect{type: :energize, misc_value: power_type} = effect,
         now
       )
       when is_integer(power_type) and power_type >= 0 do
    amount = rolled_amount(spell, effect, context)

    if effect.implicit_target_a == :caster and state.object.guid != caster_guid do
      {state, [Event.grant_power(caster_guid, power_type, amount)]}
    else
      state = Resources.gain_power(state, power_type, amount)
      {Warrior.after_energize(state, spell, now), []}
    end
  end

  defp apply_effect(
         state,
         %CastContext{} = context,
         spell,
         %Effect{type: :create_item, misc_value: item_id} = effect,
         _now
       )
       when is_integer(item_id) and item_id > 0 do
    count = max(rolled_amount(spell, effect, context), 1)
    {state, [Event.create_item(item_id, count)]}
  end

  defp apply_effect(state, %CastContext{}, spell, %Effect{type: :script_effect}, _now) do
    case Warlock.healthstone_item(state, spell) do
      item_id when is_integer(item_id) and item_id > 0 -> {state, [Event.create_item(item_id, 1)]}
      _ -> {state, []}
    end
  end

  defp apply_effect(
         state,
         %CastContext{caster_guid: caster_guid} = context,
         spell,
         %Effect{type: :power_drain, misc_value: power_type} = effect,
         _now
       ) do
    if state.unit.power_type == power_type do
      available = max(current_power(state.unit, power_type) || 0, 0)
      drained = min(rolled_amount(spell, effect, context), available)
      unit = put_power(state.unit, power_type, available - drained)
      gained = trunc(drained * leech_multiplier(effect))
      {%{state | unit: unit}, [Event.grant_power(caster_guid, 0, gained)]}
    else
      {state, []}
    end
  end

  defp apply_effect(state, %CastContext{}, spell, %Effect{type: :interrupt_cast}, now) do
    case state do
      %{internal: %{casting: casting} = internal, unit: unit} when not is_nil(casting) ->
        if interruptible_cast?(casting) do
          state = %{
            state
            | internal: %{internal | casting: nil},
              unit: %{unit | channel_spell: 0, channel_object: 0}
          }

          state = lock_interrupted_school(state, casting, spell, now)
          {Core.mark_broadcast_update(state), [Event.object_update(:values)]}
        else
          {state, []}
        end

      _ ->
        {state, []}
    end
  end

  defp apply_effect(state, %CastContext{}, _spell, %Effect{type: :dispel_mechanic, misc_value: mechanic}, now)
       when is_integer(mechanic) and mechanic > 0 do
    spell_ids =
      for %Holder{spell: %Spell{id: id, mechanic: ^mechanic}} <- state.unit.auras || [], do: id

    case spell_ids do
      [] -> {state, []}
      ids -> Aura.remove_spells(state, ids, now)
    end
  end

  defp apply_effect(
         state,
         %CastContext{} = context,
         spell,
         %Effect{type: :dispel, misc_value: dispel_type} = effect,
         now
       ) do
    aura_count = length(state.unit.auras || [])
    count = max(rolled_amount(spell, effect, context), 1)
    {state, events} = Aura.dispel(state, dispel_type, now, dispel_polarity(context), count)

    case {length(state.unit.auras || []) < aura_count, Warlock.devour_magic_heal(spell)} do
      {true, heal_spell_id} when is_integer(heal_spell_id) ->
        {state,
         events ++
           [Event.trigger_spell(context.caster_guid, context.caster_level, context.caster_guid, heal_spell_id)]}

      _other ->
        {state, events}
    end
  end

  defp apply_effect(state, %CastContext{}, _spell, %Effect{type: :power_burn, misc_value: power_type}, _now)
       when state.unit.power_type != power_type do
    {state, []}
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :power_burn} = effect, now) do
    drained = min(rolled_amount(spell, effect, context), max(state.unit.power1 || 0, 0))

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
      health = max(rolled_amount(spell, effect, context), 1)
      mana = max(effect.misc_value || 0, 0)
      offer_resurrect(state, context, spell, health, mana)
    else
      {state, []}
    end
  end

  defp apply_effect(state, %CastContext{} = context, spell, %Effect{type: :resurrect} = effect, _now) do
    if resurrectable?(state) do
      percent = max(rolled_amount(spell, effect, context), 0) / 100
      health = max(trunc((state.unit.max_health || 1) * percent), 1)
      mana = max(trunc((state.unit.max_power1 || 0) * percent), 0)
      offer_resurrect(state, context, spell, health, mana)
    else
      {state, []}
    end
  end

  defp apply_effect(state, _context, _spell, _effect, _now), do: {state, []}

  defp trigger_target_guid(state, %CastContext{} = context, %Effect{implicit_target_a: :caster})
       when state.object.guid != context.caster_guid do
    context.caster_guid
  end

  defp trigger_target_guid(state, _context, _effect), do: state.object.guid

  defp interruptible_cast?(casting) do
    case casting do
      %{spell: %Spell{prevention_type: 1}} -> true
      _ -> false
    end
  end

  defp lock_interrupted_school(state, %{spell: %Spell{} = interrupted}, %Spell{} = interrupt, now) do
    duration = max(interrupt.duration_ms || 0, 0)

    if duration > 0 do
      Cooldowns.lock_schools(state, Spell.school_mask(interrupted), now + duration)
    else
      state
    end
  end

  defp lock_interrupted_school(state, _casting, _interrupt, _now), do: state

  defp apply_target_attack_power_bonus(state, %CastContext{} = context, %Spell{} = spell) do
    if Spell.ranged_ability?(spell) do
      bonus = Aura.flat_amount(state, :ranged_attack_power_attacker_bonus)
      %{context | attack_power: (context.attack_power || 0) + bonus}
    else
      context
    end
  end

  defp summon_duration(%Spell{duration_ms: duration_ms}) when is_integer(duration_ms) and duration_ms > 0,
    do: duration_ms

  defp summon_duration(%Spell{}), do: 3_600_000

  defp summon_effect_position(%Effect{implicit_target_a: :minion_position}, _destination, {x, y, z}, orientation) do
    {x + 0.5 * :math.cos(orientation), y + 0.5 * :math.sin(orientation), z}
  end

  defp summon_effect_position(%Effect{}, {x, y, z}, _caster_position, _orientation), do: {x, y, z}
  defp summon_effect_position(%Effect{}, nil, caster_position, _orientation), do: caster_position

  defp apply_class_dummy(state, context, spell, effect, :execute, now) do
    apply_execute(state, context, spell, effect, now)
  end

  defp apply_class_dummy(state, context, _spell, _effect, :last_stand, _now) do
    event =
      Event.trigger_spell(
        context.caster_guid,
        context.caster_level,
        state.object.guid,
        Scripts.last_stand_health_buff_id()
      )

    {state, [event]}
  end

  defp apply_class_dummy(state, context, _spell, _effect, :tame_beast_completion, _now) do
    event =
      Event.trigger_spell(
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
    {state, [Event.trigger_spell(context.caster_guid, context.caster_level, state.object.guid, spell_id)]}
  end

  defp apply_class_dummy(state, context, _spell, effect, :judgement_of_command, _now) do
    spell_id = Effect.damage_roll(effect)

    if spell_id > 1 do
      {state, [Event.trigger_spell(context.caster_guid, context.caster_level, state.object.guid, spell_id)]}
    else
      {state, []}
    end
  end

  defp apply_class_dummy(state, _context, _spell, _effect, _unscripted, _now), do: {state, []}

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
      [Event.trigger_spell(source_guid, source_level, target_guid, spell_id)]
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

  defp maybe_vanish_stealth_events(state, %Spell{} = spell) do
    if Rogue.vanish?(spell), do: vanish_stealth_events(state), else: []
  end

  defp remove_vanish_stalked(state, %Spell{} = spell, now) do
    if Rogue.vanish?(spell) do
      Aura.remove_aura_types(state, [:mod_stalked, :mod_root, :mod_decrease_speed], now)
    else
      {state, []}
    end
  end

  defp vanish_stealth_events(%{object: %{guid: guid}, unit: %{level: level}, internal: %{spellbook: spellbook}})
       when is_map(spellbook) do
    spell_id =
      spellbook
      |> Map.values()
      |> Enum.filter(&Rogue.stealth?/1)
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

  defp leech_multiplier(%Effect{multiple_value: multiple}) when is_number(multiple) and multiple > 0, do: multiple
  defp leech_multiplier(_effect), do: 1.0

  defp heal_crit?(%CastContext{spell_crit_chance: chance}, %Spell{} = spell) when is_number(chance) and chance > 0 do
    not Spell.attribute?(spell, :cant_crit) and (chance >= 100 or :rand.uniform() * 100 <= chance)
  end

  defp heal_crit?(_context, _spell), do: false

  @power_fields %{0 => :power1, 1 => :power2, 2 => :power3, 3 => :power4, 4 => :power5}

  defp current_power(unit, power_type) do
    case Map.fetch(@power_fields, power_type) do
      {:ok, field} -> Map.get(unit, field)
      :error -> nil
    end
  end

  defp put_power(unit, 0, value), do: %{unit | power1: value}
  defp put_power(unit, 1, value), do: %{unit | power2: value}
  defp put_power(unit, 2, value), do: %{unit | power3: value}
  defp put_power(unit, 3, value), do: %{unit | power4: value}
  defp put_power(unit, 4, value), do: %{unit | power5: value}
  defp put_power(unit, _power_type, _value), do: unit

  defp dispel_polarity(%CastContext{target_hostile?: true}), do: :positive
  defp dispel_polarity(%CastContext{target_hostile?: false}), do: :negative
  defp dispel_polarity(_context), do: nil

  defp healing_taken_multiplier(state, spell) do
    percent = Aura.flat_modifier(state, :mod_healing_pct, Spell.school_mask(spell))
    max(100 + percent, 0) / 100
  end

  defp apply_damage_effect(state, %CastContext{} = context, spell, %Effect{} = effect, now, opts \\ [])
       when is_integer(now) do
    base = effect_amount(spell, effect, context)
    rolled = base + damage_bonus(context, spell, effect, opts)

    rolled =
      trunc(
        rolled * (context.effect_damage_multiplier || 1.0) * (context.damage_done_multiplier || 1.0) *
          versus_damage_multiplier(state, context) * scripted_damage_multiplier(state, spell)
      )

    crit? = direct_spell_crit?(state, context, spell, opts)
    rolled = if crit?, do: rolled + versus_crit_bonus(state, context, crit_bonus(context, spell, rolled)), else: rolled

    damage = max(rolled + Aura.flat_modifier(state, :mod_damage_taken, Spell.school_mask(spell)), 0)

    school = school_atom(spell)
    resisted = school_resisted_amount(state, damage, school, context, opts)
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
        opts ++ [resisted: resisted, absorbed: absorbed, crit?: crit?]
      )

    {state, reaction_events} = spell_taken_reactions(state, context, spell, damage, crit?, opts, now)
    {state, [event | reaction_events]}
  end

  defp spell_taken_reactions(state, %CastContext{caster_guid: caster_guid}, spell, damage, crit?, opts, now)
       when is_integer(caster_guid) and is_integer(damage) and damage > 0 do
    proc_type = if Keyword.get(opts, :periodic?, false), do: :take_harmful_periodic, else: :take_harmful_spell

    Aura.reactions(state, :spell_hit_taken, %{
      attacker_guid: caster_guid,
      spell: spell,
      proc_type: proc_type,
      outcome: if(crit?, do: :crit, else: :normal),
      damage: damage,
      now: now
    })
  end

  defp spell_taken_reactions(state, _context, _spell, _damage, _crit?, _opts, _now), do: {state, []}

  defp versus_damage_multiplier(state, %CastContext{damage_done_versus: pairs}) do
    max(100 + Aura.versus_amount(pairs, creature_type_mask(state)), 0) / 100
  end

  defp versus_crit_bonus(state, %CastContext{crit_damage_versus: pairs}, bonus) do
    trunc(bonus * max(100 + Aura.versus_amount(pairs, creature_type_mask(state)), 0) / 100)
  end

  @creature_type_humanoid 7

  defp creature_type_mask(%{creature_type: creature_type}) when is_integer(creature_type) and creature_type > 0 do
    1 <<< (creature_type - 1)
  end

  defp creature_type_mask(_state), do: 1 <<< (@creature_type_humanoid - 1)

  defp scripted_damage_multiplier(state, %Spell{} = spell) do
    if Scripts.judgement_of_command_damage?(spell) do
      if Aura.has_aura?(state, :mod_stun), do: 1.0, else: 0.5
    else
      1.0
    end
  end

  defp direct_spell_crit?(state, %CastContext{spell_crit_chance: chance}, %Spell{} = spell, opts)
       when is_number(chance) do
    chance = chance + Aura.flat_amount(state, :mod_attacker_spell_crit_chance)

    chance > 0 and not Keyword.get(opts, :periodic?, false) and not Spell.attribute?(spell, :cant_crit) and
      spell.dmg_class in [1, 3] and (chance >= 100 or :rand.uniform() * 100 <= chance)
  end

  defp direct_spell_crit?(_state, _context, _spell, _opts), do: false

  defp crit_bonus(%CastContext{} = context, %Spell{} = spell, damage) do
    base_bonus = damage * (spell_crit_multiplier(spell) - 1.0)
    trunc(Modifiers.value(context.spell_modifiers, :crit_damage_bonus, base_bonus))
  end

  defp spell_crit_multiplier(%Spell{dmg_class: 3}), do: 2.0
  defp spell_crit_multiplier(%Spell{}), do: 1.5

  defp school_resisted_amount(_state, damage, _school, _context, _opts) when damage <= 0, do: 0
  defp school_resisted_amount(_state, _damage, :physical, _context, _opts), do: 0

  defp school_resisted_amount(%{unit: unit} = state, damage, school, %CastContext{} = context, opts) do
    caster_level =
      if is_integer(context.caster_level) and context.caster_level > 0, do: context.caster_level, else: 1

    resistance = max((Map.get(unit, :"#{school}_resistance") || 0) + (context.spell_penetration || 0), 0)
    target_creature? = not is_map(Map.get(state, :player))
    level_diff = (unit.level || 1) - caster_level

    SpellResist.resisted_amount(damage, resistance, caster_level,
      target_creature?: target_creature?,
      level_diff: level_diff,
      dot?: Keyword.get(opts, :periodic?, false)
    )
  end

  defp damage_bonus(%CastContext{} = context, %Spell{} = spell, %Effect{} = effect, opts) do
    if Keyword.get(opts, :periodic?, false) do
      0
    else
      school_bonus = Map.get(context.spell_damage_bonus, school_atom(spell), 0)
      Coefficient.bonus(school_bonus, spell, effect, :direct)
    end
  end

  defp school_atom(%Spell{school: school}) when is_atom(school), do: school
  defp school_atom(%Spell{} = spell), do: Enum.at(@schools, Spell.school_index(spell), :physical)

  defp school_damage_roll(%CastContext{} = context, spell, %Effect{} = effect) do
    roll =
      effect_amount(spell, effect, context) +
        eviscerate_attack_power(spell, context) +
        Druid.ferocious_bite_bonus(
          spell,
          context.attack_power,
          context.combo_points,
          context.caster_power,
          effect.damage_multiplier
        ) +
        Warrior.shield_slam_bonus(spell, effect, context.shield_block_value)

    if Scripts.ap_percent_damage?(spell) do
      trunc(roll * (context.attack_power || 0) / 100)
    else
      roll
    end
  end

  defp effect_amount(%Spell{} = spell, %Effect{} = effect, %CastContext{} = context) do
    level_units = Spell.level_units(spell, context.caster_level)

    if Scripts.finisher?(spell) do
      Effect.amount(effect, level_units, context.combo_points || 0)
    else
      Effect.roll(effect, level_units)
    end
  end

  defp rolled_amount(%Spell{} = spell, %Effect{} = effect, %CastContext{} = context) do
    Effect.roll(effect, Spell.level_units(spell, context.caster_level))
  end

  defp eviscerate_attack_power(%Spell{} = spell, %CastContext{} = context) do
    if Rogue.eviscerate?(spell) do
      trunc((context.attack_power || 0) * (context.combo_points || 0) * 0.03)
    else
      0
    end
  end

  defp weapon_roll(%CastContext{attack_time_ms: attack_time_ms} = context)
       when is_number(attack_time_ms) and attack_time_ms > 0 do
    weapon_base_roll(context) + attack_power_bonus_ms(context, attack_time_ms)
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

  defp attack_power_bonus_ms(%CastContext{attack_power: attack_power}, attack_time_ms)
       when is_integer(attack_power) and attack_power > 0 and is_integer(attack_time_ms) do
    div(attack_power * attack_time_ms, 14_000)
  end

  defp attack_power_bonus_ms(context, attack_time_ms), do: attack_power_bonus(context, attack_time_ms / 1_000)

  defp maybe_mark_defense(state, attacker_guid, outcome, now) when outcome in [:dodge, :parry, :block] do
    Reactive.mark_defense(state, attacker_guid, outcome, now)
  end

  defp maybe_mark_defense(state, _attacker_guid, _outcome, _now), do: state

  defp apply_execute(state, %CastContext{} = context, spell, %Effect{} = effect, now) do
    rage = context.caster_power || 0
    damage = rolled_amount(spell, effect, context) + trunc(rage * effect.damage_multiplier)
    damage_spell = %{spell | id: Scripts.execute_damage_spell_id()}

    {state, events} = melee_ability_damage(state, context, damage_spell, damage, now)

    {state, events ++ [Event.drain_power(context.caster_guid, 1)]}
  end

  defp melee_ability_damage(state, %CastContext{} = context, spell, damage, now) do
    school = school_atom(spell)

    damage =
      trunc(damage * (context.effect_damage_multiplier || 1.0) * (context.damage_done_multiplier || 1.0))

    unmitigated_damage =
      max(damage + Aura.flat_modifier(state, :mod_damage_taken, Spell.school_mask(spell)), 0)

    damage = mitigate_physical(state, context, school, unmitigated_damage)

    damage =
      if context.melee_crit? do
        damage + trunc(Modifiers.value(context.spell_modifiers, :crit_damage_bonus, damage * 1.0))
      else
        damage
      end

    proc_damage = if context.melee_crit?, do: unmitigated_damage * 2, else: unmitigated_damage

    {state, absorbed} =
      Core.take_damage_with_absorb(state, damage, now,
        school: school,
        source: context.caster_guid,
        threat_multiplier: damage_threat_multiplier(context)
      )

    event =
      Event.spell_damage(context.caster_guid, state.object.guid, spell, damage,
        absorbed: absorbed,
        crit?: context.melee_crit? || false,
        proc_damage: proc_damage
      )

    {state, reaction_events} = melee_ability_reactions(state, context, spell, damage - absorbed, now)
    {state, [event | reaction_events]}
  end

  defp melee_ability_reactions(state, %CastContext{} = context, %Spell{} = spell, damage, now) when damage > 0 do
    if Core.dead?(state) do
      {state, []}
    else
      Aura.reactions(state, :hit_taken, %{
        attacker_guid: context.caster_guid,
        proc_type: :take_melee_ability,
        outcome: if(context.melee_crit?, do: :crit, else: :normal),
        spell: spell,
        now: now
      })
    end
  end

  defp melee_ability_reactions(state, _context, _spell, _damage, _now), do: {state, []}

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
      %Event{type: :spell_damage, damage: damage, absorbed: absorbed}, acc when is_integer(damage) ->
        acc + max(damage - (absorbed || 0), 0)

      _event, acc ->
        acc
    end)
  end

  defp dealt_proc_damage(events) do
    Enum.reduce(events, 0, fn
      %Event{type: :spell_damage, proc_damage: proc_damage, damage: damage, absorbed: absorbed}, acc
      when is_integer(proc_damage) and is_integer(damage) and damage > 0 ->
        acc + round(proc_damage * max(damage - (absorbed || 0), 0) / damage)

      %Event{type: :spell_damage, damage: damage, absorbed: absorbed}, acc when is_integer(damage) ->
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

  defp consume_conflagrate_immolate({state, events}, %CastContext{caster_guid: caster_guid}, spell, now) do
    if Warlock.conflagrate?(spell) do
      {state, aura_events} = Warlock.consume_immolate(state, caster_guid, now)
      {state, events ++ aura_events}
    else
      {state, events}
    end
  end

  defp consume_ferocious_bite_energy({state, events}, %CastContext{} = context, %Spell{} = spell) do
    if Druid.ferocious_bite?(spell) do
      {state, events ++ [Event.drain_power(context.caster_guid, 3)]}
    else
      {state, events}
    end
  end
end
