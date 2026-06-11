defmodule ThistleTea.Game.Entity.Logic.AI.BT.Spell do
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.MeleeSpell
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.Time
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
      character
      |> MeleeSpell.queue_next_swing(spell)
      |> queue_cast_result(%{spell: spell})
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
    casting = %{Cast.new(spell, targets, now) | cast_item_guid: cast_item_guid}

    character = %{character | internal: %{internal | casting: casting}}

    if Cast.channeled?(casting) do
      targets = resolve_targets(character, casting)

      character
      |> queue_cast_result(casting)
      |> queue_spell_go(casting, targets)
      |> queue_area_effects(casting)
      |> queue_consume_reagents(casting)
      |> start_channel(casting)
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
    cond do
      Cast.channeled?(casting) and now >= casting.ends_at ->
        {:success, stop_channel(character, casting), blackboard}

      Cast.channeled?(casting) ->
        {character, delay_ms} = channel_tick(character, casting, now)
        {{:running, delay_ms}, character, blackboard}

      now >= casting.ends_at ->
        character = complete_cast(character, casting, now)
        {:success, character, blackboard}

      true ->
        delay_ms = max(casting.ends_at - now, 0)
        {{:running, delay_ms}, character, blackboard}
    end
  end

  def cast_tick(character, blackboard, _now), do: {:failure, character, blackboard}

  def complete_cast(%{internal: %Internal{casting: %Cast{} = casting}} = character, now) when is_integer(now) do
    complete_cast(character, casting, now)
  end

  def complete_cast(character, now) when is_integer(now), do: character

  def complete_cast(%{internal: %Internal{}} = character, %Cast{} = casting, now) when is_integer(now) do
    targets = resolve_targets(character, casting)

    character
    |> queue_cast_result(casting)
    |> queue_spell_go(casting, targets)
    |> queue_area_effects(casting)
    |> queue_consume_reagents(casting)
    |> apply_spell_hit(casting, targets, now)
    |> clear_cast()
  end

  def complete_cast(character, _casting, _now), do: character

  def clear_cast(%{internal: %Internal{} = internal} = character) do
    case internal.casting do
      %Cast{channel_ms: channel_ms} = casting when is_integer(channel_ms) and channel_ms > 0 ->
        stop_channel(character, casting)

      _ ->
        %{character | internal: %{internal | casting: nil}}
    end
  end

  def clear_cast(character), do: character

  defp start_channel(
         %{object: %{guid: guid}, unit: unit} = character,
         %Cast{spell: %Spell{id: spell_id}, channel_ms: duration_ms} = casting
       )
       when is_integer(guid) and is_integer(duration_ms) and duration_ms > 0 do
    channel_object = channel_target_guid(character, casting.targets)

    %{character | unit: %{unit | channel_spell: spell_id, channel_object: channel_object}}
    |> Core.mark_broadcast_update()
    |> Event.enqueue([Event.channel_start(guid, spell_id, duration_ms), Event.object_update(:values)])
  end

  defp start_channel(character, _casting), do: character

  defp channel_target_guid(%{object: %{guid: guid}, unit: %{target: target}}, %Targets{unit_guid: unit_guid}) do
    cond do
      is_integer(unit_guid) and unit_guid > 0 and unit_guid != guid -> unit_guid
      is_integer(target) and target > 0 and target != guid -> target
      true -> 0
    end
  end

  defp channel_target_guid(_character, _targets), do: 0

  defp stop_channel(%{internal: %Internal{} = internal, unit: unit} = character, %Cast{} = casting) do
    character = %{character | internal: %{internal | casting: nil}, unit: %{unit | channel_object: 0, channel_spell: 0}}
    {character, aura_events} = remove_channel_auras(character, casting)

    events =
      case character do
        %{object: %{guid: guid}} when is_integer(guid) -> [Event.channel_update(guid, 0), Event.object_update(:values)]
        _ -> [Event.object_update(:values)]
      end

    character
    |> Core.mark_broadcast_update()
    |> Event.enqueue(aura_events ++ events)
  end

  defp stop_channel(%{internal: %Internal{} = internal} = character, %Cast{}) do
    %{character | internal: %{internal | casting: nil}}
  end

  defp remove_channel_auras(%{object: %{guid: guid}} = character, %Cast{spell: %Spell{id: spell_id}} = casting) do
    {character, events} =
      if channel_target_guid(character, casting.targets) in [0, guid] do
        AuraLogic.remove_spells(character, [spell_id], Time.now())
      else
        {character, []}
      end

    {character, events ++ [Event.despawn_area_effects(spell_id)]}
  end

  defp remove_channel_auras(character, _casting), do: {character, []}

  defp queue_area_effects(character, %Cast{spell: %Spell{} = spell} = casting) do
    case Targets.ground_location(casting.targets) do
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

  defp area_duration(%Cast{channel_ms: channel_ms}, _spell) when is_integer(channel_ms) and channel_ms > 0,
    do: channel_ms

  defp area_duration(_casting, %Spell{duration_ms: duration_ms}) when is_integer(duration_ms) and duration_ms > 0,
    do: duration_ms

  defp area_duration(_casting, _spell), do: 8_000

  defp queue_consume_reagents(character, %Cast{spell: %Spell{reagents: [_ | _] = reagents}}) do
    Event.enqueue(character, Event.consume_reagents(reagents))
  end

  defp queue_consume_reagents(character, _casting), do: character

  defp queue_cast_result(character, %{spell: %Spell{id: spell_id}}) do
    Event.enqueue(character, Event.spell_cast_result(spell_id))
  end

  defp queue_cast_result(character, _casting), do: character

  defp channel_tick(%{internal: %Internal{}} = character, %Cast{} = casting, now) do
    cond do
      unit_channel_target_dead?(casting) ->
        {stop_channel(character, casting), 50}

      is_integer(casting.next_channel_tick_at) and now >= casting.next_channel_tick_at ->
        targets = resolve_targets(character, casting)

        character =
          character
          |> queue_trigger_spell_go(casting, targets)
          |> apply_spell_hit(casting, targets, now)

        casting = Cast.advance_channel_tick(casting, now)
        delay_ms = Cast.next_channel_delay(casting, now)
        {%{character | internal: %{character.internal | casting: casting}}, delay_ms}

      true ->
        {character, Cast.next_channel_delay(casting, now)}
    end
  end

  defp channel_tick(character, casting, now), do: {character, Cast.next_channel_delay(casting, now)}

  defp unit_channel_target_dead?(%Cast{targets: %Targets{unit_guid: guid}}) when is_integer(guid) and guid > 0 do
    case Metadata.query(guid, [:alive?]) do
      %{alive?: false} -> true
      _ -> false
    end
  end

  defp unit_channel_target_dead?(_casting), do: false

  defp queue_spell_go(%{object: %{guid: guid}} = character, %Cast{spell: %Spell{id: spell_id}} = casting, targets)
       when is_integer(guid) do
    raw_targets = if is_binary(casting.targets.raw), do: casting.targets.raw, else: <<>>

    Event.enqueue(character, Event.spell_go(guid, spell_id, targets, raw_targets, casting.cast_item_guid))
  end

  defp queue_spell_go(character, _casting, _targets), do: character

  defp queue_trigger_spell_go(
         %{object: %{guid: guid}} = character,
         %Cast{spell: %Spell{effects: effects}} = casting,
         targets
       )
       when is_integer(guid) do
    hits = redirect_self_hits(character, targets)

    raw_targets =
      case hits do
        [hit] when hit != guid -> Targets.unit(hit).raw
        _ -> if is_binary(casting.targets.raw), do: casting.targets.raw, else: <<>>
      end

    events =
      for %Spell.Effect{type: :apply_aura, aura: :periodic_trigger_spell, trigger_spell_id: spell_id} <- effects,
          is_integer(spell_id) and spell_id > 0 do
        Event.spell_go(guid, spell_id, hits, raw_targets)
      end

    Event.enqueue(character, events)
  end

  defp queue_trigger_spell_go(character, _casting, _targets), do: character

  defp redirect_self_hits(%{object: %{guid: guid}, unit: %{channel_object: channel_object}}, [guid])
       when is_integer(channel_object) and channel_object > 0 and channel_object != guid do
    [channel_object]
  end

  defp redirect_self_hits(_character, targets), do: targets

  defp apply_spell_hit(%{object: %{guid: caster_guid}} = character, %Cast{spell: %Spell{} = spell}, targets, now)
       when is_integer(caster_guid) and is_list(targets) do
    Enum.reduce(targets, character, fn target_guid, caster ->
      context = CastContext.from_caster(caster, spell, target_guid)
      dispatch_to_target(caster, context, spell, target_guid, now)
    end)
  end

  defp apply_spell_hit(character, _casting, _targets, _now), do: character

  defp dispatch_to_target(character, %CastContext{caster_guid: caster_guid} = context, spell, target_guid, now)
       when target_guid == caster_guid do
    {character, events} = SpellEffect.receive(character, context, spell, now)
    duration_events = AuraLogic.self_duration_events(character)

    character
    |> Event.enqueue(events ++ duration_events)
    |> queue_self_update()
  end

  defp dispatch_to_target(character, %CastContext{} = context, spell, target_guid, _now) when is_integer(target_guid) do
    Event.enqueue(character, Event.deliver_spell(target_guid, context, spell))
  end

  defp dispatch_to_target(character, _context, _spell, _target_guid, _now), do: character

  defp resolve_targets(caster, %Cast{spell: %Spell{} = spell, targets: %Targets{} = targets}) do
    query = SpellTarget.target_query(spell, targets)
    SpellTargetResolver.resolve_query(caster, query)
  end

  defp resolve_targets(_caster, _casting), do: []

  defp queue_self_update(%{internal: %Internal{broadcast_update?: true}} = character) do
    Event.enqueue(character, Event.object_update(:values))
  end

  defp queue_self_update(character), do: character
end
