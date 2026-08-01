defmodule ThistleTea.Game.Entity.Logic.Casting do
  @moduledoc """
  Entity transitions for the spell-cast state machine.

  The behavior tree schedules these transitions; this module owns preparation,
  launch, impact, channel ticks, and finish.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Hunter
  alias ThistleTea.Game.Entity.Logic.MeleeSpell
  alias ThistleTea.Game.Entity.Logic.Paladin
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.CastResolution
  alias ThistleTea.Game.Spell.CastResolution.Costs
  alias ThistleTea.Game.Spell.CastResolution.Followups
  alias ThistleTea.Game.Spell.CastResolution.Impact
  alias ThistleTea.Game.Spell.CastResolution.PowerCost
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Scripts
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  def start(entity, spell, targets, now, cast_item_guid \\ nil)

  def start(%{internal: %Internal{} = internal} = character, %Spell{} = spell, %Target{} = targets, now, cast_item_guid)
      when is_integer(now) do
    if Spell.attribute?(spell, :on_next_swing) do
      MeleeSpell.queue_next_swing(character, spell)
    else
      do_start(character, internal, spell, targets, now, cast_item_guid)
    end
  end

  def start(entity, _spell, _targets, _now, _cast_item_guid), do: entity

  defp do_start(
         %{internal: %Internal{} = internal} = character,
         %Internal{},
         %Spell{} = spell,
         %Target{} = targets,
         now,
         cast_item_guid
       ) do
    modifier_holder_ids = Modifiers.consumable_holder_ids(character, spell)
    spell = %{spell | cast_time_ms: Modifiers.integer_value(character, spell, :casting_time, spell.cast_time_ms || 0)}

    casting =
      spell
      |> Cast.new(targets, now)
      |> Cast.apply_speed_modifier(AuraLogic.flat_amount(character, :mod_casting_speed))
      |> then(&%{&1 | cast_item_guid: cast_item_guid, modifier_holder_ids: modifier_holder_ids})

    character = %{character | internal: %{internal | casting: casting}}
    character = Cooldowns.trigger_gcd(character, spell, now)

    if casting.cast_time_ms == 0 and Cast.channeled?(casting) do
      case advance(character, now) do
        {:waiting, character, _delay_ms} -> character
        {:finished, character} -> character
      end
    else
      character
    end
  end

  def advance(%{internal: %Internal{casting: %Cast{} = casting}} = entity, now) when is_integer(now) do
    advance_phase(entity, casting, now)
  end

  def advance(entity, _now), do: {:idle, entity}

  def complete(%{internal: %Internal{casting: %Cast{} = casting}} = entity, now) when is_integer(now) do
    complete(entity, casting, now)
  end

  def complete(entity, now) when is_integer(now), do: entity

  def complete(%{internal: %Internal{} = internal} = entity, %Cast{} = casting, now) when is_integer(now) do
    entity = %{entity | internal: %{internal | casting: casting}}

    case advance_phase(entity, casting, max(now, Cast.launch_at(casting))) do
      {:waiting, entity, _delay_ms} -> entity
      {:finished, entity} -> entity
    end
  end

  def complete(entity, _casting, _now), do: entity

  defp advance_phase(entity, %Cast{phase: :preparing} = casting, now) do
    if now >= Cast.launch_at(casting) do
      launch(entity, casting, now)
    else
      {:waiting, entity, Cast.launch_at(casting) - now}
    end
  end

  defp advance_phase(entity, %Cast{phase: :launch} = casting, now) do
    apply_launch(entity, casting, now)
  end

  defp advance_phase(entity, %Cast{phase: :impact} = casting, now) do
    apply_impact(entity, casting, now)
  end

  defp advance_phase(entity, %Cast{phase: :channel_tick} = casting, now) do
    if now >= casting.ends_at do
      casting = Cast.transition(casting, :finish)
      entity |> put_cast(casting) |> advance_phase(casting, now)
    else
      {entity, delay_ms} = channel_tick(entity, casting, now)

      case entity.internal.casting do
        %Cast{} -> {:waiting, entity, delay_ms}
        nil -> {:finished, entity}
      end
    end
  end

  defp advance_phase(entity, %Cast{phase: :finish} = casting, now) do
    {:finished, finish(entity, casting, now)}
  end

  defp launch(entity, %Cast{} = casting, now) do
    if cast_target_visible?(entity, casting) do
      resolution = resolve(entity, casting)

      casting =
        casting
        |> Cast.transition(:launch)
        |> Cast.put_resolution(resolution)

      entity
      |> put_cast(casting)
      |> advance_phase(casting, now)
    else
      entity =
        entity
        |> Effects.enqueue(Effects.spell_cast_failed(Cast.spell_id(casting), :line_of_sight))
        |> cancel()

      {:finished, entity}
    end
  end

  defp apply_launch(entity, %Cast{resolution: %CastResolution{} = resolution} = casting, now) do
    attempted_targets = resolution.hits ++ Enum.map(resolution.misses, & &1.guid)

    entity =
      entity
      |> spend_power_cost(resolution.costs.power, now)
      |> start_cooldown(casting, now)
      |> queue_cast_result(casting)
      |> queue_spell_go(casting, resolution.followups.packet_hits, resolution.misses)
      |> queue_spell_miss_outcomes(casting, resolution.misses)
      |> queue_consume_costs(resolution.costs)
      |> break_stealth(casting, now)
      |> mark_hostile_cast(casting, attempted_targets, now)

    casting = Cast.transition(casting, :impact)
    entity |> put_cast(casting) |> advance_phase(casting, now)
  end

  defp apply_impact(entity, %Cast{resolution: %CastResolution{} = resolution} = casting, now) do
    entity =
      entity
      |> queue_target_triggers(casting, resolution.hits)
      |> queue_area_effects(casting)
      |> queue_farsight(casting)
      |> queue_summon_objects(casting)
      |> queue_item_enchantments(casting)
      |> queue_feed_pet(casting)
      |> queue_open_object(casting)
      |> queue_charge(casting)
      |> release_paladin_seal(casting, resolution.hits, now)
      |> apply_impacts(casting, resolution.impacts, now)
      |> consume_spell_modifiers(casting, now)

    if Cast.channeled?(casting) do
      casting = Cast.transition(casting, :channel_tick)
      entity = entity |> put_cast(casting) |> start_channel(casting)

      if valid_channel_target?(casting) do
        {:waiting, entity, Cast.next_channel_delay(casting, now)}
      else
        {:finished, stop_channel(entity, casting)}
      end
    else
      casting = Cast.transition(casting, :finish)
      entity |> put_cast(casting) |> advance_phase(casting, now)
    end
  end

  defp finish(entity, %Cast{resolution: %CastResolution{} = resolution} = casting, now) do
    entity =
      entity
      |> queue_successful_finish_trigger(casting)
      |> queue_quest_cast_credit(casting, resolution)
      |> stop_breakable_control_attack(casting, resolution.hits)
      |> consume_unavoidable_finisher(casting)
      |> activate_auto_shot(casting, now)

    if Cast.channeled?(casting) do
      stop_channel(entity, casting, :completed)
    else
      cancel(entity)
    end
  end

  defp queue_quest_cast_credit(%Character{} = character, %Cast{spell: %Spell{id: spell_id}}, %CastResolution{
         hits: hits,
         followups: %Followups{object_guid: object_guid}
       }) do
    targets =
      case object_guid do
        guid when is_integer(guid) and guid > 0 -> Enum.uniq([guid | hits])
        _guid -> hits
      end

    Effects.enqueue(character, Effects.quest_cast_credit(targets, spell_id))
  end

  defp queue_quest_cast_credit(entity, _casting, _resolution), do: entity

  defp resolve(entity, %Cast{spell: %Spell{} = spell, targets: %Target{} = targets} = casting) do
    resolved_targets = resolve_targets(entity, casting)
    {hits, misses} = roll_spell_hits(entity, spell, resolved_targets)
    object_guid = Target.object_guid(targets)

    %CastResolution{
      hits: hits,
      misses: misses,
      costs: %Costs{
        power: power_cost(entity, spell),
        channel_power: channel_power_cost(entity, casting),
        reagents: spell.reagents || [],
        ammo: Hunter.ammo_reagents(entity, spell),
        cast_item_guid: cast_item_cost(casting),
        modifier_holder_ids: casting.modifier_holder_ids
      },
      impacts:
        Enum.map(hits, fn target_guid ->
          %Impact{target_guid: target_guid, target_role: target_role(entity, target_guid)}
        end),
      followups: %Followups{
        packet_hits: hits ++ object_hit(object_guid),
        selected_unit_guid: Target.unit_guid(targets),
        object_guid: object_guid,
        item_guid: Target.item_guid(targets),
        ground_position: Target.ground_location(targets),
        area_position: area_effect_position(entity, spell, targets)
      }
    }
  end

  defp empty_resolution(object_guid) do
    %CastResolution{
      hits: [],
      misses: [],
      costs: %Costs{
        power: %PowerCost{power_type: nil, amount: 0},
        channel_power: %PowerCost{power_type: nil, amount: 0},
        reagents: [],
        ammo: [],
        cast_item_guid: nil,
        modifier_holder_ids: []
      },
      impacts: [],
      followups: %Followups{
        packet_hits: object_hit(object_guid),
        selected_unit_guid: nil,
        object_guid: object_guid,
        item_guid: nil,
        ground_position: nil,
        area_position: nil
      }
    }
  end

  defp object_hit(guid) when is_integer(guid), do: [guid]
  defp object_hit(_guid), do: []

  defp cast_item_cost(%Cast{consume_item: true, cast_item_guid: item_guid}) when is_integer(item_guid), do: item_guid
  defp cast_item_cost(%Cast{}), do: nil

  defp power_cost(entity, %Spell{} = spell) do
    %PowerCost{power_type: spell.power_type, amount: Resources.power_cost(entity, spell)}
  end

  defp channel_power_cost(entity, %Cast{spell: %Spell{} = spell, channel_tick_ms: tick_ms}) do
    %PowerCost{power_type: spell.power_type, amount: Resources.channel_cost(entity, spell, tick_ms)}
  end

  defp spend_power_cost(entity, %PowerCost{} = cost, now) do
    Resources.spend_cost(entity, cost.power_type, cost.amount, now)
  end

  defp put_cast(%{internal: %Internal{} = internal} = entity, %Cast{} = casting) do
    %{entity | internal: %{internal | casting: casting}}
  end

  defp stop_breakable_control_attack(%Character{} = character, %Cast{spell: %Spell{} = spell}, [target_guid | _]) do
    if Spell.breaks_on_damage?(spell) do
      character
      |> BT.clear_auto_attack()
      |> then(&%{&1 | internal: %{&1.internal | auto_shot: nil}})
      |> Effects.enqueue(Effects.attack_stop(character.object.guid, target_guid))
    else
      character
    end
  end

  defp stop_breakable_control_attack(character, _casting, _hits), do: character

  defp queue_successful_finish_trigger(%{object: %{guid: guid}, unit: %{level: level}} = character, %Cast{
         spell: %Spell{} = spell
       }) do
    case Semantics.rules(spell).finish_trigger_spell_id do
      spell_id when is_integer(spell_id) ->
        Effects.enqueue(character, Effects.trigger_spell(guid, level || 1, guid, spell_id, resolve_targets?: true))

      _none ->
        character
    end
  end

  defp queue_successful_finish_trigger(character, _casting), do: character

  defp activate_auto_shot(
         %Character{internal: %Internal{} = internal} = character,
         %Cast{spell: %Spell{} = spell, targets: %Target{} = targets},
         now
       ) do
    target_guid = Target.unit_guid(targets)

    if Hunter.auto_shot?(spell) and is_integer(target_guid) and target_guid > 0 do
      auto_shot = %{
        spell: spell,
        target_guid: target_guid,
        targets: targets,
        next_at: now + character.unit.ranged_attack_time
      }

      %{character | internal: %{internal | auto_shot: auto_shot}}
    else
      character
    end
  end

  defp activate_auto_shot(character, _casting, _now), do: character

  defp release_paladin_seal(character, %Cast{spell: %Spell{} = spell}, [target_guid | _rest], now) do
    Paladin.release_seal(character, spell, target_guid, now)
  end

  defp release_paladin_seal(character, _casting, _hits, _now), do: character

  defp queue_charge(character, %Cast{
         spell: %Spell{} = spell,
         resolution: %CastResolution{followups: %Followups{selected_unit_guid: unit_guid}}
       }) do
    if is_integer(unit_guid) and unit_guid > 0 and Enum.any?(spell.effects, &(&1.type == :charge)) do
      Effects.enqueue(character, Effects.charge(unit_guid))
    else
      character
    end
  end

  defp consume_spell_modifiers(
         character,
         %Cast{resolution: %CastResolution{costs: %Costs{modifier_holder_ids: [_ | _] = spell_ids}}},
         now
       ) do
    {character, events} = AuraLogic.spend_spell_charges(character, spell_ids, now)
    Effects.enqueue(character, events)
  end

  defp consume_spell_modifiers(character, %Cast{}, _now), do: character

  defp consume_unavoidable_finisher(character, %Cast{spell: %Spell{} = spell}) do
    if Scripts.finisher?(spell) and not Spell.melee_ability?(spell) do
      Reactive.consume_combo(character)
    else
      character
    end
  end

  defp queue_open_object(character, %Cast{
         spell: %Spell{} = spell,
         resolution: %CastResolution{followups: %Followups{object_guid: object_guid}}
       }) do
    if is_integer(object_guid) and Enum.any?(spell.effects, &(&1.type == :open_lock)) do
      Effects.enqueue(character, Effects.open_gameobject(object_guid))
    else
      character
    end
  end

  defp queue_feed_pet(%Character{} = character, %Cast{
         spell: %Spell{range_yards: range_yards, effects: effects},
         resolution: %CastResolution{followups: %Followups{item_guid: item_guid}}
       }) do
    pet_guid = Companion.summon_guid(character)

    case {pet_guid, item_guid, Enum.find(effects, &(&1.type == :feed_pet and is_integer(&1.trigger_spell_id)))} do
      {pet_guid, item_guid, %Spell.Effect{trigger_spell_id: trigger_spell_id}}
      when is_integer(pet_guid) and pet_guid > 0 and is_integer(item_guid) ->
        Effects.enqueue(character, Effects.feed_pet(item_guid, pet_guid, trigger_spell_id, range_yards))

      _ ->
        character
    end
  end

  defp queue_feed_pet(character, _casting), do: character

  defp queue_item_enchantments(%Character{player: player} = character, %Cast{
         spell: %Spell{} = spell,
         resolution: %CastResolution{followups: %Followups{item_guid: target_item_guid}}
       }) do
    item_guid = if is_integer(target_item_guid), do: target_item_guid, else: player.mainhand

    events =
      for %Spell.Effect{type: :enchant_item_temporary} = effect <- spell.effects,
          is_integer(item_guid) do
        Effects.enchant_item(item_guid, spell, effect)
      end

    Effects.enqueue(character, events)
  end

  defp queue_item_enchantments(character, %Cast{
         spell: %Spell{} = spell,
         resolution: %CastResolution{followups: %Followups{item_guid: item_guid}}
       }) do
    events =
      for %Spell.Effect{type: :enchant_item_temporary} = effect <- spell.effects,
          is_integer(item_guid) do
        Effects.enchant_item(item_guid, spell, effect)
      end

    Effects.enqueue(character, events)
  end

  defp mark_hostile_cast(%Character{object: %{guid: guid}} = character, %Cast{spell: spell}, targets, now) do
    if Spell.harmful?(spell) and Enum.any?(targets, &(&1 != guid)) do
      PlayerCombat.mark_initiated(character, now)
    else
      character
    end
  end

  defp mark_hostile_cast(character, _casting, _targets, _now), do: character

  defp break_stealth(character, %Cast{spell: %Spell{} = spell}, now) do
    if Spell.harmful?(spell) do
      {character, events} = AuraLogic.remove_with_interrupt_flags(character, AuraLogic.interrupt_mask(:cast), now)
      Effects.enqueue(character, events)
    else
      character
    end
  end

  def cancel(%{internal: %Internal{} = internal} = character) do
    case internal.casting do
      %Cast{channel_ms: channel_ms} = casting when is_integer(channel_ms) and channel_ms > 0 ->
        stop_channel(character, casting)

      _ ->
        %{character | internal: %{internal | casting: nil}}
    end
  end

  def cancel(character), do: character

  def start_game_object_channel(
        %{internal: %Internal{} = internal, unit: unit, object: %{guid: guid}} = character,
        game_object_guid,
        %Spell{id: spell_id} = spell,
        duration_ms,
        now
      )
      when is_integer(game_object_guid) and is_integer(duration_ms) and duration_ms > 0 and is_integer(now) do
    spell = %{spell | duration_ms: duration_ms, attributes: MapSet.put(spell.attributes, :channeled)}

    casting =
      spell
      |> Cast.new(Target.object(game_object_guid), now)
      |> Cast.transition(:launch)
      |> Cast.put_resolution(empty_resolution(game_object_guid))
      |> Cast.transition(:impact)
      |> Cast.transition(:channel_tick)

    %{
      character
      | internal: %{
          internal
          | casting: casting,
            channel_game_object_guid: game_object_guid,
            channel_game_object_owned?: false
        },
        unit: %{unit | channel_spell: spell_id, channel_object: game_object_guid}
    }
    |> Core.mark_broadcast_update()
    |> Effects.enqueue(Effects.channel_start(guid, spell_id, duration_ms))
  end

  def start_game_object_channel(character, _game_object_guid, _spell, _duration_ms, _now), do: character

  def finish_game_object_channel(
        %{internal: %Internal{channel_game_object_guid: game_object_guid, casting: %Cast{} = casting}} = character,
        game_object_guid
      ) do
    stop_channel(character, casting, :completed)
  end

  def finish_game_object_channel(character, _game_object_guid), do: character

  defp start_channel(
         %{object: %{guid: guid}, unit: unit} = character,
         %Cast{spell: %Spell{id: spell_id}, channel_ms: duration_ms} = casting
       )
       when is_integer(guid) and is_integer(duration_ms) and duration_ms > 0 do
    channel_object = channel_target_guid(character, casting)

    %{character | unit: %{unit | channel_spell: spell_id, channel_object: channel_object}}
    |> Core.mark_broadcast_update()
    |> Effects.enqueue(Effects.channel_start(guid, spell_id, duration_ms))
  end

  defp start_channel(character, _casting), do: character

  defp channel_target_guid(%{object: %{guid: guid}, unit: %{target: target}} = character, %Cast{
         spell: %Spell{effects: effects},
         targets: %Target{} = targets
       }) do
    unit_guid = Target.unit_guid(targets)
    pet_guid = if is_struct(character, Character), do: Companion.summon_guid(character)

    case pet_channel_target(pet_guid, effects) do
      nil -> preferred_channel_target(guid, unit_guid, target)
      pet_guid -> pet_guid
    end
  end

  defp channel_target_guid(_character, _casting), do: 0

  defp pet_channel_target(pet_guid, effects) when is_integer(pet_guid) and pet_guid > 0 do
    if Enum.any?(effects, &(&1.implicit_target_a == :pet or &1.implicit_target_b == :pet)), do: pet_guid
  end

  defp pet_channel_target(_pet_guid, _effects), do: nil

  defp preferred_channel_target(self_guid, unit_guid, target) do
    cond do
      is_integer(unit_guid) and unit_guid > 0 and unit_guid != self_guid -> unit_guid
      is_integer(target) and target > 0 and target != self_guid -> target
      true -> 0
    end
  end

  defp stop_channel(character, casting), do: stop_channel(character, casting, :cancelled)

  defp stop_channel(
         %{object: %{guid: user_guid}, internal: %Internal{} = internal, unit: unit} = character,
         %Cast{} = casting,
         reason
       ) do
    channel_game_object_guid = internal.channel_game_object_guid
    channel_game_object_owned? = internal.channel_game_object_owned?

    character = %{
      character
      | internal: %{
          internal
          | casting: nil,
            channel_game_object_guid: nil,
            channel_game_object_owned?: nil
        },
        unit: %{unit | channel_object: 0, channel_spell: 0}
    }

    {character, aura_events} = channel_aura_events(character, casting, reason)

    object_events = channel_object_events(channel_game_object_guid, channel_game_object_owned?, user_guid, reason)

    events =
      case character do
        %{object: %{guid: guid}} when is_integer(guid) ->
          [Effects.channel_update(guid, 0)]

        _ ->
          []
      end

    character
    |> Core.mark_broadcast_update()
    |> Effects.enqueue(aura_events ++ object_events ++ events)
  end

  defp stop_channel(%{internal: %Internal{} = internal} = character, %Cast{}, _reason) do
    %{character | internal: %{internal | casting: nil}}
  end

  defp channel_object_events(_guid, _owned?, _user_guid, :completed), do: []

  defp channel_object_events(guid, true, _user_guid, :cancelled) when is_integer(guid) do
    [Effects.despawn_entity(guid)]
  end

  defp channel_object_events(guid, false, user_guid, :cancelled) when is_integer(guid) do
    [Effects.leave_ritual(guid, user_guid)]
  end

  defp channel_object_events(_guid, _owned?, _user_guid, _reason), do: []

  defp channel_aura_events(character, _casting, :completed), do: {character, []}
  defp channel_aura_events(character, casting, :cancelled), do: remove_channel_auras(character, casting)

  defp remove_channel_auras(%{object: %{guid: guid}} = character, %Cast{spell: %Spell{id: spell_id}} = casting) do
    target_guid = channel_target_guid(character, casting)
    {character, events} = AuraLogic.remove_source_spell(character, spell_id, guid, Time.now())

    remote_events =
      if target_guid > 0 and target_guid != guid do
        [Effects.remove_aura(guid, target_guid, spell_id)]
      else
        []
      end

    {character, events ++ remote_events ++ [Effects.despawn_area_effects(spell_id)]}
  end

  defp remove_channel_auras(character, _casting), do: {character, []}

  defp queue_area_effects(
         character,
         %Cast{spell: %Spell{} = spell, resolution: %CastResolution{followups: %Followups{area_position: position}}} =
           casting
       ) do
    case position do
      nil ->
        character

      position ->
        events =
          for %Spell.Effect{type: :persistent_area_aura} = effect <- spell.effects do
            Effects.spawn_area_effect(spell, effect, position, area_duration(casting, spell))
          end

        Effects.enqueue(character, events)
    end
  end

  defp queue_area_effects(character, _casting), do: character

  defp queue_farsight(character, %Cast{
         spell: %Spell{} = spell,
         resolution: %CastResolution{followups: %Followups{ground_position: position}}
       }) do
    if Enum.any?(spell.effects, &(&1.type == :add_farsight)) do
      case position do
        {x, y, z} -> Effects.enqueue(character, Effects.spawn_farsight(spell, {x, y, z}, spell.duration_ms || 0))
        _ -> character
      end
    else
      character
    end
  end

  defp queue_farsight(character, _casting), do: character

  defp area_effect_position(character, %Spell{} = spell, %Target{} = targets) do
    Target.ground_location(targets) || caster_area_position(character, spell)
  end

  defp area_effect_position(_character, _spell, _targets), do: nil

  defp caster_area_position(%{movement_block: %{position: {x, y, z, _o}}}, %Spell{effects: effects}) do
    if Enum.any?(effects, &(&1.implicit_target_a == :caster_destination or &1.implicit_target_b == :caster_destination)) do
      {x, y, z}
    end
  end

  defp caster_area_position(_character, _spell), do: nil

  defp area_duration(%Cast{channel_ms: channel_ms}, _spell) when is_integer(channel_ms) and channel_ms > 0,
    do: channel_ms

  defp area_duration(_casting, %Spell{duration_ms: duration_ms}) when is_integer(duration_ms) and duration_ms > 0,
    do: duration_ms

  defp area_duration(_casting, _spell), do: 8_000

  defp queue_target_triggers(character, %Cast{spell: %Spell{} = spell}, hits) when is_list(hits) do
    Effects.enqueue(character, AuraLogic.target_trigger_events(character, spell, hits))
  end

  defp queue_target_triggers(character, _casting, _hits), do: character

  defp queue_summon_objects(
         character,
         %Cast{
           spell: %Spell{} = spell,
           resolution: %CastResolution{followups: %Followups{selected_unit_guid: selected_unit_guid}}
         } = casting
       ) do
    target_guid = selected_unit_guid || character.unit.target

    events =
      for %Spell.Effect{type: :trans_door, misc_value: entry} <- spell.effects,
          is_integer(entry) and entry > 0 do
        Effects.summon_game_object(entry, area_duration(casting, spell), ritual_target_guid: target_guid)
      end

    Effects.enqueue(character, events)
  end

  defp queue_consume_costs(character, %Costs{} = costs) do
    character
    |> queue_reagents(costs.reagents)
    |> queue_reagents(costs.ammo)
    |> queue_cast_item(costs.cast_item_guid)
  end

  defp queue_reagents(character, [_ | _] = reagents) do
    Effects.enqueue(character, Effects.consume_reagents(reagents))
  end

  defp queue_reagents(character, _reagents), do: character

  defp queue_cast_item(character, item_guid) when is_integer(item_guid) do
    Effects.enqueue(character, Effects.consume_cast_item(item_guid))
  end

  defp queue_cast_item(character, _item_guid), do: character

  defp start_cooldown(character, %Cast{spell: %Spell{} = spell}, now) do
    Cooldowns.start(character, spell, now)
  end

  defp start_cooldown(character, _casting, _now), do: character

  defp queue_cast_result(character, %{spell: %Spell{id: spell_id}}) do
    Effects.enqueue(character, Effects.spell_cast_result(spell_id))
  end

  defp queue_cast_result(character, _casting), do: character

  defp channel_tick(%{internal: %Internal{}} = character, %Cast{} = casting, now) do
    cond do
      unit_channel_target_dead?(character, casting) ->
        {stop_channel(character, casting), 50}

      not unit_channel_target_in_range?(character, casting) ->
        {stop_channel(character, casting), 50}

      is_integer(casting.next_channel_tick_at) and now >= casting.next_channel_tick_at ->
        pay_and_apply_channel_tick(character, casting, now)

      true ->
        {character, Cast.next_channel_delay(casting, now)}
    end
  end

  defp channel_tick(character, casting, now), do: {character, Cast.next_channel_delay(casting, now)}

  defp pay_and_apply_channel_tick(character, %Cast{} = casting, now) do
    cost = casting.resolution.costs.channel_power

    if Resources.can_pay_cost?(character, cost.power_type, cost.amount) do
      character =
        character
        |> spend_power_cost(cost, now)
        |> apply_channel_tick_effects(casting, now)

      casting = Cast.advance_channel_tick(casting, now)
      delay_ms = Cast.next_channel_delay(casting, now)
      {%{character | internal: %{character.internal | casting: casting}}, delay_ms}
    else
      {stop_channel(character, casting), 50}
    end
  end

  defp unit_channel_target_dead?(%{unit: %{channel_object: guid}}, %Cast{}) when is_integer(guid) and guid > 0 do
    dead_target?(guid)
  end

  defp unit_channel_target_dead?(_character, %Cast{targets: %Target{} = targets}) do
    case Target.unit_guid(targets) do
      guid when is_integer(guid) and guid > 0 -> dead_target?(guid)
      _none -> false
    end
  end

  defp unit_channel_target_dead?(_character, _casting), do: false

  defp valid_channel_target?(%Cast{
         spell: %Spell{} = spell,
         targets: %Target{} = targets,
         resolution: %CastResolution{hits: hits}
       }) do
    if Spell.target_dependent_channel?(spell) do
      case Target.unit_guid(targets) do
        guid when is_integer(guid) and guid > 0 -> guid in hits
        _none -> hits != []
      end
    else
      true
    end
  end

  defp valid_channel_target?(_casting), do: true

  defp unit_channel_target_in_range?(character, %Cast{spell: %Spell{} = spell} = casting) do
    case unit_channel_target_guid(character, casting) do
      guid when is_integer(guid) and guid > 0 ->
        metadata =
          case Metadata.query(guid, [:combat_reach, :faction_template]) do
            nil -> %{}
            metadata -> metadata
          end

        target_info =
          metadata
          |> Map.put(:position, World.position(guid))
          |> Map.put(:hostile?, channel_target_hostile?(character, guid, spell, metadata))

        CastValidation.channel_in_range?(character, spell, target_info)

      _none ->
        true
    end
  end

  defp unit_channel_target_in_range?(_character, _casting), do: true

  defp channel_target_hostile?(character, guid, %Spell{} = spell, metadata) do
    case metadata do
      %{faction_template: _faction_template} ->
        Hostility.hostile?(character, Map.put(metadata, :guid, guid))

      _unknown ->
        Spell.harmful?(spell)
    end
  end

  defp unit_channel_target_guid(%{unit: %{channel_object: guid}}, %Cast{}) when is_integer(guid) and guid > 0, do: guid

  defp unit_channel_target_guid(_character, %Cast{targets: %Target{} = targets}), do: Target.unit_guid(targets)
  defp unit_channel_target_guid(_character, _casting), do: nil

  defp dead_target?(guid) do
    case Metadata.query(guid, [:alive?]) do
      %{alive?: false} -> true
      _ -> false
    end
  end

  defp cast_target_visible?(%{object: %{guid: self_guid}} = character, %Cast{
         spell: %Spell{} = spell,
         targets: %Target{} = targets
       }) do
    unit_guid = Target.unit_guid(targets)

    if is_integer(unit_guid) and unit_guid > 0 and unit_guid != self_guid do
      Spell.attribute?(spell, :ignore_line_of_sight) or World.line_of_sight?(character, unit_guid)
    else
      true
    end
  end

  defp cast_target_visible?(_character, _casting), do: true

  defp queue_spell_go(character, casting, targets, misses)

  defp queue_spell_go(
         %{object: %{guid: guid}} = character,
         %Cast{spell: %Spell{id: spell_id}} = casting,
         targets,
         misses
       )
       when is_integer(guid) do
    Effects.enqueue(
      character,
      Effects.spell_go(guid, spell_id, targets, casting.targets, casting.cast_item_guid, misses)
    )
  end

  defp queue_spell_go(character, _casting, _targets, _misses), do: character

  @spell_miss_reason_miss 1
  @spell_miss_reason_resist 2

  defp queue_spell_miss_outcomes(%{object: %{guid: caster_guid}} = character, %Cast{spell: %Spell{} = spell}, misses)
       when is_integer(caster_guid) and is_list(misses) do
    events =
      for %{guid: target_guid, reason: @spell_miss_reason_resist} <- misses do
        Effects.deliver_spell_outcome(target_guid, caster_guid, spell, :resist)
      end

    Effects.enqueue(character, events)
  end

  defp queue_spell_miss_outcomes(character, _casting, _misses), do: character

  defp roll_spell_hits(_caster, %Spell{dmg_class: 2}, targets), do: {targets, []}
  defp roll_spell_hits(_caster, %Spell{dmg_class: 3}, targets), do: {targets, []}

  defp roll_spell_hits(%{object: %{guid: caster_guid}} = caster, %Spell{} = spell, targets) do
    if Spell.harmful?(spell) do
      caster_level = caster_level(caster)
      hit_bonus = spell_hit_bonus(caster, spell)

      {hits, missed} =
        Enum.split_with(targets, fn target_guid ->
          target_guid == caster_guid or
            not Hostility.valid_attack_target?(caster, target_guid) or
            spell_hits_target?(caster_level, target_guid, hit_bonus, spell)
        end)

      {hits, Enum.map(missed, &%{guid: &1, reason: spell_miss_reason(spell)})}
    else
      {targets, []}
    end
  end

  defp roll_spell_hits(_caster, _spell, targets), do: {targets, []}

  defp spell_hit_bonus(caster, %Spell{} = spell) do
    AuraLogic.flat_amount(caster, :mod_spell_hit_chance) +
      Modifiers.value(caster, spell, :resist_miss_chance, 0)
  end

  defp spell_hits_target?(caster_level, target_guid, hit_bonus, %Spell{} = spell) do
    target_player? = Guid.type_id(target_guid) == :player

    metadata = Metadata.query(target_guid, [:level, :attacker_spell_hit_chance])
    target_level = target_level(metadata, caster_level)

    target_hit_modifier =
      case metadata do
        %{attacker_spell_hit_chance: modifiers} ->
          AuraLogic.versus_amount(modifiers, Spell.school_mask(spell))

        _ ->
          0
      end

    SpellResist.magic_hit?(caster_level, target_level, target_player?, hit_bonus: hit_bonus + target_hit_modifier)
  end

  defp target_level(%{level: level}, _caster_level) when is_integer(level) and level > 0, do: level
  defp target_level(_metadata, caster_level), do: caster_level

  defp spell_miss_reason(%Spell{school: :physical}), do: @spell_miss_reason_miss
  defp spell_miss_reason(%Spell{school: 0}), do: @spell_miss_reason_miss
  defp spell_miss_reason(_spell), do: @spell_miss_reason_resist

  defp caster_level(%{unit: %{level: level}}) when is_integer(level) and level > 0, do: level
  defp caster_level(_caster), do: 1

  defp apply_channel_tick_effects(
         character,
         %Cast{spell: %Spell{} = spell, resolution: %CastResolution{impacts: impacts}} = casting,
         now
       ) do
    case Spell.channel_ticked_effects(spell) do
      [] ->
        character

      tick_effects ->
        apply_impacts(character, %{casting | spell: %{spell | effects: tick_effects}}, impacts, now)
    end
  end

  defp apply_channel_tick_effects(character, _casting, _now), do: character

  defp apply_impacts(
         %{object: %{guid: caster_guid}} = character,
         %Cast{spell: %Spell{} = spell} = casting,
         impacts,
         now
       )
       when is_integer(caster_guid) and is_list(impacts) do
    Enum.reduce(impacts, character, fn %Impact{target_guid: target_guid, target_role: target_role}, caster ->
      context = %{
        CastContext.from_caster(caster, spell, target_guid)
        | selected_target_guid: Target.unit_guid(casting.targets),
          destination_position: Target.ground_location(casting.targets),
          target_hostile?: target_guid != caster_guid and Hostility.valid_attack_target?(caster, target_guid),
          target_role: target_role
      }

      dispatch_to_target(caster, context, spell, target_guid, now)
    end)
  end

  defp apply_impacts(character, _casting, _impacts, _now), do: character

  defp target_role(%{object: %{guid: guid}}, guid), do: :caster

  defp target_role(%Character{} = caster, target_guid) do
    if Companion.summon_guid(caster) == target_guid, do: :pet, else: :other
  end

  defp target_role(_caster, _target_guid), do: :other

  defp dispatch_to_target(character, %CastContext{caster_guid: caster_guid} = context, spell, target_guid, now)
       when target_guid == caster_guid do
    {character, events} = SpellEffect.receive(character, context, spell, now)

    character
    |> Effects.enqueue(events)
  end

  defp dispatch_to_target(character, %CastContext{} = context, spell, target_guid, _now) when is_integer(target_guid) do
    Effects.enqueue(character, Effects.deliver_spell(target_guid, context, spell))
  end

  defp dispatch_to_target(character, _context, _spell, _target_guid, _now), do: character

  defp resolve_targets(caster, %Cast{spell: %Spell{} = spell, targets: %Target{} = targets}) do
    resolved = SpellTargetResolver.resolve(caster, spell, targets)

    if Enum.any?(spell.effects, &(&1.implicit_target_a == :caster or &1.implicit_target_b == :caster)) do
      Enum.uniq([caster.object.guid | resolved])
    else
      resolved
    end
  end
end
