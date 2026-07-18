defmodule ThistleTea.Game.Entity.Logic.AI.BT.Spell do
  @moduledoc """
  Spell-casting behavior-tree subtree: starting a cast (validation, cast time,
  power cost) and ticking it through completion or channel ticks.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
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
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Scripts
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  def casting_sequence do
    BT.sequence([
      BT.condition(&casting?/2),
      BT.action(&cast_tick/2)
    ])
  end

  def start_cast(character, spell, targets, now, cast_item_guid \\ nil)

  def start_cast(
        %{internal: %Internal{} = internal} = character,
        %Spell{} = spell,
        %Targets{} = targets,
        now,
        cast_item_guid
      )
      when is_integer(now) do
    if Spell.attribute?(spell, :on_next_swing) do
      MeleeSpell.queue_next_swing(character, spell)
    else
      do_start_cast(character, internal, spell, targets, now, cast_item_guid)
    end
  end

  def start_cast(character, _spell, _targets, _now, _cast_item_guid) do
    character
  end

  defp do_start_cast(
         %{internal: %Internal{} = internal} = character,
         %Internal{},
         %Spell{} = spell,
         %Targets{} = targets,
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

    if Cast.channeled?(casting) and casting.cast_time_ms == 0 do
      begin_channel(character, casting, now)
    else
      character
    end
  end

  def casting?(%{internal: %Internal{casting: %Cast{}}}, _blackboard) do
    true
  end

  def casting?(_character, _blackboard), do: false

  def cast_tick(%{internal: %Internal{casting: casting}} = character, %Blackboard{} = blackboard)
      when is_struct(casting, Cast) do
    cast_tick(character, blackboard, Time.now())
  end

  def cast_tick(character, blackboard), do: {:failure, character, blackboard}

  def cast_tick(%{internal: %Internal{casting: casting}} = character, %Blackboard{} = blackboard, now)
      when is_struct(casting, Cast) and is_integer(now) do
    if Cast.channeled?(casting) do
      channeled_cast_tick(character, casting, blackboard, now)
    else
      regular_cast_tick(character, casting, blackboard, now)
    end
  end

  def cast_tick(character, blackboard, _now), do: {:failure, character, blackboard}

  defp channeled_cast_tick(character, casting, blackboard, now) do
    cond do
      not casting.channel_started? and now >= casting.started_at + casting.cast_time_ms ->
        character = begin_channel(character, casting, now)
        delay_ms = Cast.next_channel_delay(character.internal.casting, now)
        {{:running, delay_ms}, character, blackboard}

      not casting.channel_started? ->
        delay_ms = max(casting.started_at + casting.cast_time_ms - now, 0)
        {{:running, delay_ms}, character, blackboard}

      now >= casting.ends_at ->
        {:success, stop_channel(character, casting, :completed), blackboard}

      true ->
        {character, delay_ms} = channel_tick(character, casting, now)
        {{:running, delay_ms}, character, blackboard}
    end
  end

  defp regular_cast_tick(character, casting, blackboard, now) do
    if now >= casting.ends_at do
      character = complete_cast(character, casting, now)
      {:success, character, blackboard}
    else
      delay_ms = max(casting.ends_at - now, 0)
      {{:running, delay_ms}, character, blackboard}
    end
  end

  def complete_cast(%{internal: %Internal{casting: %Cast{} = casting}} = character, now) when is_integer(now) do
    complete_cast(character, casting, now)
  end

  def complete_cast(character, now) when is_integer(now), do: character

  def complete_cast(%{internal: %Internal{}} = character, %Cast{} = casting, now) when is_integer(now) do
    if cast_target_visible?(character, casting) do
      do_complete_cast(character, casting, now)
    else
      character
      |> Event.enqueue(Event.spell_cast_failed(Cast.spell_id(casting), :line_of_sight))
      |> clear_cast()
    end
  end

  def complete_cast(character, _casting, _now), do: character

  defp do_complete_cast(character, %Cast{} = casting, now) do
    targets = resolve_targets(character, casting)
    {hits, misses} = roll_spell_hits(character, casting.spell, targets)

    character
    |> Resources.spend_power(casting.spell, now)
    |> start_cooldown(casting, now)
    |> queue_cast_result(casting)
    |> queue_spell_go(casting, hits ++ object_hits(casting), misses)
    |> queue_target_triggers(casting, hits)
    |> queue_area_effects(casting)
    |> queue_farsight(casting)
    |> queue_summon_objects(casting)
    |> queue_item_enchantments(casting)
    |> queue_consume_reagents(casting)
    |> queue_consume_ammo(casting)
    |> queue_feed_pet(casting)
    |> queue_consume_cast_item(casting)
    |> queue_open_object(casting)
    |> break_stealth(casting, now)
    |> mark_hostile_cast(casting, targets, now)
    |> queue_charge(casting)
    |> release_paladin_seal(casting, hits, now)
    |> apply_spell_hit(casting, hits, now)
    |> queue_successful_finish_trigger(casting)
    |> stop_breakable_control_attack(casting, hits)
    |> consume_unavoidable_finisher(casting)
    |> consume_spell_modifiers(casting, now)
    |> activate_auto_shot(casting, now)
    |> clear_cast()
  end

  defp stop_breakable_control_attack(%Character{} = character, %Cast{spell: %Spell{} = spell}, [target_guid | _]) do
    if Spell.breaks_on_damage?(spell) do
      character
      |> BT.clear_auto_attack()
      |> then(&%{&1 | internal: %{&1.internal | auto_shot: nil}})
      |> Event.enqueue(Event.attack_stop(character.object.guid, target_guid))
    else
      character
    end
  end

  defp stop_breakable_control_attack(character, _casting, _hits), do: character

  defp queue_successful_finish_trigger(%{object: %{guid: guid}, unit: %{level: level}} = character, %Cast{
         spell: %Spell{} = spell
       }) do
    case Scripts.successful_finish_trigger(spell) do
      spell_id when is_integer(spell_id) ->
        Event.enqueue(character, Event.trigger_spell(guid, level || 1, guid, spell_id, resolve_targets?: true))

      _none ->
        character
    end
  end

  defp queue_successful_finish_trigger(character, _casting), do: character

  defp activate_auto_shot(
         %Character{internal: %Internal{} = internal} = character,
         %Cast{spell: %Spell{} = spell, targets: %Targets{unit_guid: target_guid, raw: raw}},
         now
       )
       when is_integer(target_guid) and target_guid > 0 do
    if Hunter.auto_shot?(spell) do
      auto_shot = %{
        spell: spell,
        target_guid: target_guid,
        raw_targets: raw,
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

  defp queue_charge(character, %Cast{spell: %Spell{} = spell, targets: %Targets{unit_guid: unit_guid}})
       when is_integer(unit_guid) and unit_guid > 0 do
    if Enum.any?(spell.effects, &(&1.type == :charge)) do
      Event.enqueue(character, Event.charge(unit_guid))
    else
      character
    end
  end

  defp queue_charge(character, _casting), do: character

  defp consume_spell_modifiers(character, %Cast{modifier_holder_ids: [_ | _] = spell_ids}, now) do
    {character, events} = AuraLogic.spend_spell_charges(character, spell_ids, now)
    Event.enqueue(character, events)
  end

  defp consume_spell_modifiers(character, %Cast{spell: %Spell{} = spell}, now) do
    spell_ids = Modifiers.consumable_holder_ids(character, spell)
    {character, events} = AuraLogic.spend_spell_charges(character, spell_ids, now)
    Event.enqueue(character, events)
  end

  defp consume_unavoidable_finisher(character, %Cast{spell: %Spell{} = spell}) do
    if Scripts.finisher?(spell) and not Spell.melee_ability?(spell) do
      Reactive.consume_combo(character)
    else
      character
    end
  end

  defp queue_open_object(character, %Cast{spell: %Spell{} = spell, targets: %Targets{object_guid: object_guid}})
       when is_integer(object_guid) do
    if Enum.any?(spell.effects, &(&1.type == :open_lock)) do
      Event.enqueue(character, Event.open_gameobject(object_guid))
    else
      character
    end
  end

  defp queue_open_object(character, %Cast{}), do: character

  defp object_hits(%Cast{targets: %Targets{object_guid: object_guid}}) when is_integer(object_guid) do
    [object_guid]
  end

  defp object_hits(%Cast{}), do: []

  defp queue_consume_cast_item(character, %Cast{consume_item: true, cast_item_guid: item_guid})
       when is_integer(item_guid) do
    Event.enqueue(character, Event.consume_cast_item(item_guid))
  end

  defp queue_consume_cast_item(character, %Cast{}), do: character

  defp queue_feed_pet(%Character{unit: %{summon: pet_guid}} = character, %Cast{
         spell: %Spell{range_yards: range_yards, effects: effects},
         targets: %Targets{item_guid: item_guid}
       })
       when is_integer(pet_guid) and pet_guid > 0 and is_integer(item_guid) do
    case Enum.find(effects, &(&1.type == :feed_pet and is_integer(&1.trigger_spell_id))) do
      %Spell.Effect{trigger_spell_id: trigger_spell_id} ->
        Event.enqueue(character, Event.feed_pet(item_guid, pet_guid, trigger_spell_id, range_yards))

      _ ->
        character
    end
  end

  defp queue_feed_pet(character, _casting), do: character

  defp queue_item_enchantments(%Character{player: player} = character, %Cast{
         spell: %Spell{} = spell,
         targets: %Targets{item_guid: target_item_guid}
       }) do
    item_guid = if is_integer(target_item_guid), do: target_item_guid, else: player.mainhand

    events =
      for %Spell.Effect{type: :enchant_item_temporary} = effect <- spell.effects,
          is_integer(item_guid) do
        Event.enchant_item(item_guid, spell, effect)
      end

    Event.enqueue(character, events)
  end

  defp queue_item_enchantments(character, %Cast{spell: %Spell{} = spell, targets: %Targets{item_guid: item_guid}})
       when is_integer(item_guid) do
    events =
      for %Spell.Effect{type: :enchant_item_temporary} = effect <- spell.effects do
        Event.enchant_item(item_guid, spell, effect)
      end

    Event.enqueue(character, events)
  end

  defp queue_item_enchantments(character, _casting), do: character

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
      Event.enqueue(character, events)
    else
      character
    end
  end

  def clear_cast(%{internal: %Internal{} = internal} = character) do
    case internal.casting do
      %Cast{channel_ms: channel_ms} = casting when is_integer(channel_ms) and channel_ms > 0 ->
        stop_channel(character, casting)

      _ ->
        %{character | internal: %{internal | casting: nil}}
    end
  end

  def clear_cast(character), do: character

  def start_game_object_channel(
        %{internal: %Internal{} = internal, unit: unit, object: %{guid: guid}} = character,
        game_object_guid,
        %Spell{id: spell_id} = spell,
        duration_ms,
        now
      )
      when is_integer(game_object_guid) and is_integer(duration_ms) and duration_ms > 0 and is_integer(now) do
    spell = %{spell | duration_ms: duration_ms, attributes: MapSet.put(spell.attributes, :channeled)}
    casting = Cast.new(spell, %Targets{object_guid: game_object_guid}, now)

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
    |> Event.enqueue([Event.channel_start(guid, spell_id, duration_ms), Event.object_update(:values)])
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
    |> Event.enqueue([Event.channel_start(guid, spell_id, duration_ms), Event.object_update(:values)])
  end

  defp start_channel(character, _casting), do: character

  defp channel_target_guid(%{object: %{guid: guid}, unit: %{target: target, summon: pet_guid}}, %Cast{
         spell: %Spell{effects: effects},
         targets: %Targets{unit_guid: unit_guid}
       }) do
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
        %{object: %{guid: guid}} when is_integer(guid) -> [Event.channel_update(guid, 0), Event.object_update(:values)]
        _ -> [Event.object_update(:values)]
      end

    character
    |> Core.mark_broadcast_update()
    |> Event.enqueue(aura_events ++ object_events ++ events)
  end

  defp stop_channel(%{internal: %Internal{} = internal} = character, %Cast{}, _reason) do
    %{character | internal: %{internal | casting: nil}}
  end

  defp channel_object_events(_guid, _owned?, _user_guid, :completed), do: []

  defp channel_object_events(guid, true, _user_guid, :cancelled) when is_integer(guid) do
    [Event.despawn_entity(guid)]
  end

  defp channel_object_events(guid, false, user_guid, :cancelled) when is_integer(guid) do
    [Event.leave_ritual(guid, user_guid)]
  end

  defp channel_object_events(_guid, _owned?, _user_guid, _reason), do: []

  defp channel_aura_events(character, _casting, :completed), do: {character, []}
  defp channel_aura_events(character, casting, :cancelled), do: remove_channel_auras(character, casting)

  defp remove_channel_auras(%{object: %{guid: guid}} = character, %Cast{spell: %Spell{id: spell_id}} = casting) do
    target_guid = channel_target_guid(character, casting)
    {character, events} = AuraLogic.remove_source_spell(character, spell_id, guid, Time.now())

    remote_events =
      if target_guid > 0 and target_guid != guid do
        [Event.remove_aura(guid, target_guid, spell_id)]
      else
        []
      end

    {character, events ++ remote_events ++ [Event.despawn_area_effects(spell_id)]}
  end

  defp remove_channel_auras(character, _casting), do: {character, []}

  defp queue_area_effects(character, %Cast{spell: %Spell{} = spell} = casting) do
    case area_effect_position(character, spell, casting.targets) do
      nil ->
        character

      position ->
        events =
          for %Spell.Effect{type: :persistent_area_aura} = effect <- spell.effects do
            Event.spawn_area_effect(spell, effect, position, area_duration(casting, spell))
          end

        Event.enqueue(character, events)
    end
  end

  defp queue_area_effects(character, _casting), do: character

  defp queue_farsight(character, %Cast{spell: %Spell{} = spell, targets: %Targets{} = targets}) do
    if Enum.any?(spell.effects, &(&1.type == :add_farsight)) do
      case Targets.ground_location(targets) do
        {x, y, z} -> Event.enqueue(character, Event.spawn_farsight(spell, {x, y, z}, spell.duration_ms || 0))
        _ -> character
      end
    else
      character
    end
  end

  defp queue_farsight(character, _casting), do: character

  defp area_effect_position(character, %Spell{} = spell, %Targets{} = targets) do
    Targets.ground_location(targets) || caster_area_position(character, spell)
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
    Event.enqueue(character, AuraLogic.target_trigger_events(character, spell, hits))
  end

  defp queue_target_triggers(character, _casting, _hits), do: character

  defp queue_summon_objects(character, %Cast{spell: %Spell{} = spell} = casting) do
    target_guid = casting.targets.unit_guid || character.unit.target

    events =
      for %Spell.Effect{type: :trans_door, misc_value: entry} <- spell.effects,
          is_integer(entry) and entry > 0 do
        Event.summon_game_object(entry, area_duration(casting, spell), ritual_target_guid: target_guid)
      end

    Event.enqueue(character, events)
  end

  defp queue_consume_reagents(character, %Cast{spell: %Spell{reagents: [_ | _] = reagents}}) do
    Event.enqueue(character, Event.consume_reagents(reagents))
  end

  defp queue_consume_reagents(character, _casting), do: character

  defp queue_consume_ammo(character, %Cast{spell: %Spell{} = spell}) do
    case Hunter.ammo_reagents(character, spell) do
      [] -> character
      reagents -> Event.enqueue(character, Event.consume_reagents(reagents))
    end
  end

  defp start_cooldown(character, %Cast{spell: %Spell{} = spell}, now) do
    Cooldowns.start(character, spell, now)
  end

  defp start_cooldown(character, _casting, _now), do: character

  defp queue_cast_result(character, %{spell: %Spell{id: spell_id}}) do
    Event.enqueue(character, Event.spell_cast_result(spell_id))
  end

  defp queue_cast_result(character, _casting), do: character

  defp begin_channel(%{internal: %Internal{} = internal} = character, %Cast{} = casting, now) do
    casting = %{casting | channel_started?: true}
    character = %{character | internal: %{internal | casting: casting}}
    targets = resolve_targets(character, casting)
    {hits, misses} = roll_spell_hits(character, casting.spell, targets)

    character
    |> Resources.spend_power(casting.spell, now)
    |> start_cooldown(casting, now)
    |> queue_cast_result(casting)
    |> queue_spell_go(casting, hits ++ object_hits(casting), misses)
    |> queue_target_triggers(casting, hits)
    |> queue_area_effects(casting)
    |> queue_summon_objects(casting)
    |> queue_consume_reagents(casting)
    |> queue_consume_ammo(casting)
    |> mark_hostile_cast(casting, hits, now)
    |> apply_spell_hit(casting, hits, now)
    |> consume_spell_modifiers(casting, now)
    |> start_channel(casting)
  end

  defp channel_tick(%{internal: %Internal{}} = character, %Cast{} = casting, now) do
    cond do
      unit_channel_target_dead?(casting) ->
        {stop_channel(character, casting), 50}

      not cast_target_visible?(character, casting) ->
        {stop_channel(character, casting), 50}

      is_integer(casting.next_channel_tick_at) and now >= casting.next_channel_tick_at ->
        pay_and_apply_channel_tick(character, casting, now)

      true ->
        {character, Cast.next_channel_delay(casting, now)}
    end
  end

  defp channel_tick(character, casting, now), do: {character, Cast.next_channel_delay(casting, now)}

  defp pay_and_apply_channel_tick(character, %Cast{} = casting, now) do
    if Resources.can_pay_channel_cost?(character, casting.spell, casting.channel_tick_ms) do
      character =
        character
        |> Resources.spend_channel_cost(casting.spell, casting.channel_tick_ms, now)

      casting = Cast.advance_channel_tick(casting, now)
      delay_ms = Cast.next_channel_delay(casting, now)
      {%{character | internal: %{character.internal | casting: casting}}, delay_ms}
    else
      {stop_channel(character, casting), 50}
    end
  end

  defp unit_channel_target_dead?(%Cast{targets: %Targets{unit_guid: guid}}) when is_integer(guid) and guid > 0 do
    case Metadata.query(guid, [:alive?]) do
      %{alive?: false} -> true
      _ -> false
    end
  end

  defp unit_channel_target_dead?(_casting), do: false

  defp cast_target_visible?(%{object: %{guid: self_guid}} = character, %Cast{
         spell: %Spell{} = spell,
         targets: %Targets{unit_guid: unit_guid}
       })
       when is_integer(unit_guid) and unit_guid > 0 and unit_guid != self_guid do
    Spell.attribute?(spell, :ignore_line_of_sight) or World.line_of_sight?(character, unit_guid)
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
    raw_targets = if is_binary(casting.targets.raw), do: casting.targets.raw, else: <<>>

    Event.enqueue(character, Event.spell_go(guid, spell_id, targets, raw_targets, casting.cast_item_guid, misses))
  end

  defp queue_spell_go(character, _casting, _targets, _misses), do: character

  @spell_miss_reason_miss 1
  @spell_miss_reason_resist 2

  defp roll_spell_hits(_caster, %Spell{dmg_class: 2}, targets), do: {targets, []}

  defp roll_spell_hits(%{object: %{guid: caster_guid}} = caster, %Spell{} = spell, targets) do
    if Spell.harmful?(spell) do
      caster_level = caster_level(caster)
      hit_bonus = spell_hit_bonus(caster, spell)

      {hits, missed} =
        Enum.split_with(targets, fn target_guid ->
          target_guid == caster_guid or
            not Hostility.valid_attack_target?(caster, target_guid) or
            spell_hits_target?(caster_level, target_guid, hit_bonus)
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

  defp spell_hits_target?(caster_level, target_guid, hit_bonus) do
    target_player? = Guid.type_id(target_guid) == :player

    target_level =
      case Metadata.query(target_guid, [:level]) do
        %{level: level} when is_integer(level) and level > 0 -> level
        _ -> caster_level
      end

    SpellResist.magic_hit?(caster_level, target_level, target_player?, hit_bonus: hit_bonus)
  end

  defp spell_miss_reason(%Spell{school: :physical}), do: @spell_miss_reason_miss
  defp spell_miss_reason(%Spell{school: 0}), do: @spell_miss_reason_miss
  defp spell_miss_reason(_spell), do: @spell_miss_reason_resist

  defp caster_level(%{unit: %{level: level}}) when is_integer(level) and level > 0, do: level
  defp caster_level(_caster), do: 1

  defp apply_spell_hit(
         %{object: %{guid: caster_guid}} = character,
         %Cast{spell: %Spell{} = spell} = casting,
         targets,
         now
       )
       when is_integer(caster_guid) and is_list(targets) do
    Enum.reduce(targets, character, fn target_guid, caster ->
      context = %{
        CastContext.from_caster(caster, spell, target_guid)
        | selected_target_guid: casting.targets.unit_guid,
          destination_position: Targets.ground_location(casting.targets),
          target_hostile?: target_guid != caster_guid and Hostility.valid_attack_target?(caster, target_guid),
          target_role: target_role(caster, target_guid)
      }

      dispatch_to_target(caster, context, spell, target_guid, now)
    end)
  end

  defp apply_spell_hit(character, _casting, _targets, _now), do: character

  defp target_role(%{object: %{guid: guid}}, guid), do: :caster
  defp target_role(%{unit: %{summon: pet_guid}}, pet_guid) when is_integer(pet_guid) and pet_guid > 0, do: :pet
  defp target_role(_caster, _target_guid), do: :other

  defp dispatch_to_target(character, %CastContext{caster_guid: caster_guid} = context, spell, target_guid, now)
       when target_guid == caster_guid do
    {character, events} = SpellEffect.receive(character, context, spell, now)

    character
    |> Event.enqueue(events)
    |> queue_self_update()
  end

  defp dispatch_to_target(character, %CastContext{} = context, spell, target_guid, _now) when is_integer(target_guid) do
    Event.enqueue(character, Event.deliver_spell(target_guid, context, spell))
  end

  defp dispatch_to_target(character, _context, _spell, _target_guid, _now), do: character

  defp resolve_targets(caster, %Cast{spell: %Spell{} = spell, targets: %Targets{} = targets}) do
    resolved = SpellTargetResolver.resolve(caster, spell, targets)

    if Enum.any?(spell.effects, &(&1.implicit_target_a == :caster or &1.implicit_target_b == :caster)) do
      Enum.uniq([caster.object.guid | resolved])
    else
      resolved
    end
  end

  defp resolve_targets(_caster, _casting), do: []

  defp queue_self_update(%{internal: %Internal{broadcast_update?: true}} = character) do
    Event.enqueue(character, Event.object_update(:values))
  end

  defp queue_self_update(character), do: character
end
