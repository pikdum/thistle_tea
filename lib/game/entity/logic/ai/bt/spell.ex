defmodule ThistleTea.Game.Entity.Logic.AI.BT.Spell do
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.MeleeSpell
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World

  def casting_sequence do
    BT.sequence([
      BT.condition(&casting?/2),
      BT.action(&cast_tick/2)
    ])
  end

  def start_cast(%{internal: %Internal{} = internal} = character, %Spell{} = spell, %Targets{} = targets) do
    if Spell.attribute?(spell, :on_next_swing) do
      MeleeSpell.queue_next_swing(character, spell)
    else
      do_start_cast(character, internal, spell, targets)
    end
  end

  def start_cast(character, _spell, _targets) do
    character
  end

  defp do_start_cast(
         %{internal: %Internal{} = internal} = character,
         %Internal{},
         %Spell{} = spell,
         %Targets{} = targets
       ) do
    now = Time.now()
    cast_time_ms = normalize_time(spell.cast_time_ms)

    channel_ms =
      if Spell.attribute?(spell, :channeled), do: normalize_time(spell.duration_ms), else: 0

    channel_tick_ms = if channel_ms > 0, do: Spell.channel_tick_ms(spell)

    casting = %{
      spell: spell,
      targets: targets,
      cast_time_ms: cast_time_ms,
      channel_ms: channel_ms,
      channel_tick_ms: channel_tick_ms,
      next_channel_tick_at: next_channel_tick_at(now, cast_time_ms, channel_tick_ms),
      channel_go_sent?: false,
      started_at: now,
      ends_at: now + cast_time_ms + channel_ms
    }

    %{character | internal: %{internal | casting: casting}}
  end

  def casting?(%{internal: %Internal{casting: %{} = casting}}, _blackboard) when is_map(casting) do
    true
  end

  def casting?(_character, _blackboard), do: false

  def cast_tick(%{internal: %Internal{casting: casting}} = character, %Blackboard{} = blackboard)
      when is_map(casting) do
    now = Time.now()
    ends_at = Map.get(casting, :ends_at, now)

    cond do
      channeled?(casting) and now >= ends_at ->
        {:success, clear_cast(character), blackboard}

      channeled?(casting) ->
        {character, delay_ms} = channel_tick(character, casting, now)
        {{:running, delay_ms}, character, blackboard}

      now >= ends_at ->
        character = complete_cast(character, casting)
        {:success, character, blackboard}

      true ->
        delay_ms = max(ends_at - now, 0)
        {{:running, delay_ms}, character, blackboard}
    end
  end

  def cast_tick(character, blackboard), do: {:failure, character, blackboard}

  def complete_cast(%{internal: %Internal{casting: casting}} = character) when is_map(casting) do
    complete_cast(character, casting)
  end

  def complete_cast(character), do: character

  def complete_cast(%{internal: %Internal{} = internal} = character, casting) when is_map(casting) do
    character
    |> send_cast_result(casting)
    |> send_spell_go(casting)
    |> apply_spell_hit(casting)
    |> clear_casting(internal)
  end

  def complete_cast(character, _casting), do: character

  def clear_cast(%{internal: %Internal{} = internal} = character) do
    %{character | internal: %{internal | casting: nil}}
  end

  def clear_cast(character), do: character

  defp send_cast_result(character, %{spell: %Spell{id: spell_id}}) do
    Network.send_packet(%Message.SmsgCastResult{
      spell: spell_id,
      result: 0,
      reason: nil,
      required_spell_focus: nil,
      area: nil,
      equipped_item_class: nil,
      equipped_item_subclass_mask: nil,
      equipped_item_inventory_type_mask: nil
    })

    character
  end

  defp send_cast_result(character, _casting), do: character

  defp channel_tick(%{internal: %Internal{}} = character, casting, now) do
    next_tick_at = Map.get(casting, :next_channel_tick_at)

    if is_integer(next_tick_at) and now >= next_tick_at do
      character =
        character
        |> maybe_send_channel_spell_go(casting)
        |> apply_spell_hit(casting)

      casting = advance_channel_tick(casting, now)
      delay_ms = next_channel_delay(casting, now)
      {%{character | internal: %{character.internal | casting: casting}}, delay_ms}
    else
      {character, next_channel_delay(casting, now)}
    end
  end

  defp channel_tick(character, casting, now), do: {character, next_channel_delay(casting, now)}

  defp maybe_send_channel_spell_go(character, %{channel_go_sent?: false} = casting) do
    send_spell_go(character, casting)
  end

  defp maybe_send_channel_spell_go(character, _casting), do: character

  defp advance_channel_tick(%{channel_tick_ms: tick_ms, next_channel_tick_at: next_tick_at} = casting, now)
       when is_integer(tick_ms) and tick_ms > 0 and is_integer(next_tick_at) do
    %{casting | next_channel_tick_at: advance_tick(next_tick_at, tick_ms, now), channel_go_sent?: true}
  end

  defp advance_channel_tick(casting, _now), do: casting

  defp advance_tick(last_tick, tick_ms, now) do
    next = last_tick + tick_ms
    if next > now, do: next, else: advance_tick(next, tick_ms, now)
  end

  defp next_channel_delay(%{ends_at: ends_at, next_channel_tick_at: next_tick_at}, now)
       when is_integer(ends_at) and is_integer(next_tick_at) do
    min(max(next_tick_at - now, 0), max(ends_at - now, 0))
  end

  defp next_channel_delay(%{ends_at: ends_at}, now) when is_integer(ends_at), do: max(ends_at - now, 0)
  defp next_channel_delay(_casting, _now), do: 0

  defp channeled?(%{channel_ms: channel_ms}) when is_integer(channel_ms) and channel_ms > 0, do: true
  defp channeled?(_casting), do: false

  defp send_spell_go(%{object: %{guid: guid}} = character, %{spell: %Spell{id: spell_id}} = casting)
       when is_integer(guid) do
    hits = resolve_targets(character, casting)

    %Message.SmsgSpellGo{
      cast_item: guid,
      caster: guid,
      spell: spell_id,
      flags: 0x100,
      hits: hits,
      misses: [],
      targets: casting.targets.raw,
      ammo_display_id: nil,
      ammo_inventory_type: nil
    }
    |> World.broadcast_packet(character)

    character
  end

  defp send_spell_go(character, _casting), do: character

  defp apply_spell_hit(%{object: %{guid: caster_guid}} = character, %{spell: %Spell{} = spell} = casting)
       when is_integer(caster_guid) do
    targets = resolve_targets(character, casting)

    Enum.reduce(targets, character, fn target_guid, caster ->
      context = CastContext.from_caster(caster, spell, target_guid)
      dispatch_to_target(caster, context, spell, target_guid)
    end)
  end

  defp apply_spell_hit(character, _casting), do: character

  defp dispatch_to_target(character, %CastContext{caster_guid: caster_guid} = context, spell, target_guid)
       when target_guid == caster_guid do
    {character, events} = SpellEffect.receive(character, context, spell)
    duration_events = AuraLogic.self_duration_events(character)

    character
    |> EventSink.emit(events ++ duration_events)
    |> broadcast_self_update()
  end

  defp dispatch_to_target(character, %CastContext{} = context, spell, target_guid) when is_integer(target_guid) do
    Entity.receive_spell(target_guid, context, spell)
    character
  end

  defp dispatch_to_target(character, _context, _spell, _target_guid), do: character

  defp resolve_targets(caster, %{spell: %Spell{} = spell, targets: %Targets{} = targets}) do
    SpellTarget.resolve(caster, spell, targets)
  end

  defp resolve_targets(_caster, _casting), do: []

  defp broadcast_self_update(%{internal: %Internal{broadcast_update?: true} = internal} = character) do
    Core.update_object(character, :values)
    |> World.broadcast_packet(character)

    %{character | internal: %{internal | broadcast_update?: false}}
  end

  defp broadcast_self_update(character), do: character

  defp clear_casting(character, internal) do
    %{character | internal: %{internal | casting: nil}}
  end

  defp normalize_time(value) when is_integer(value) and value > 0, do: value
  defp normalize_time(_value), do: 0

  defp next_channel_tick_at(_now, _cast_time_ms, nil), do: nil
  defp next_channel_tick_at(now, cast_time_ms, tick_ms), do: now + cast_time_ms + tick_ms
end
