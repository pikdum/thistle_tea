defmodule ThistleTea.Game.Entity.Logic.AI.BT.Spell do
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.MeleeSpell
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.Time

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
    %{character | internal: %{internal | casting: Cast.new(spell, targets, now)}}
  end

  def casting?(%{internal: %Internal{casting: %Cast{}}}, _blackboard) do
    true
  end

  def casting?(_character, _blackboard), do: false

  def cast_tick(%{internal: %Internal{casting: casting}} = character, %Blackboard{} = blackboard)
      when is_struct(casting, Cast) do
    now = Time.now()

    cond do
      Cast.channeled?(casting) and now >= casting.ends_at ->
        {:success, clear_cast(character), blackboard}

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

  def cast_tick(character, blackboard), do: {:failure, character, blackboard}

  def complete_cast(%{internal: %Internal{casting: %Cast{} = casting}} = character) do
    complete_cast(character, casting, Time.now())
  end

  def complete_cast(character), do: character

  def complete_cast(%{internal: %Internal{casting: %Cast{} = casting}} = character, now) when is_integer(now) do
    complete_cast(character, casting, now)
  end

  def complete_cast(%{internal: %Internal{}} = character, %Cast{} = casting) do
    complete_cast(character, casting, Time.now())
  end

  def complete_cast(character, _casting), do: character

  def complete_cast(%{internal: %Internal{}} = character, %Cast{} = casting, now) when is_integer(now) do
    targets = resolve_targets(character, casting)

    character
    |> queue_cast_result(casting)
    |> queue_spell_go(casting, targets)
    |> apply_spell_hit(casting, targets, now)
    |> clear_cast()
  end

  def complete_cast(character, _casting, _now), do: character

  def clear_cast(%{internal: %Internal{} = internal} = character) do
    %{character | internal: %{internal | casting: nil}}
  end

  def clear_cast(character), do: character

  defp queue_cast_result(character, %{spell: %Spell{id: spell_id}}) do
    Event.enqueue(character, Event.spell_cast_result(spell_id))
  end

  defp queue_cast_result(character, _casting), do: character

  defp channel_tick(%{internal: %Internal{}} = character, %Cast{} = casting, now) do
    if is_integer(casting.next_channel_tick_at) and now >= casting.next_channel_tick_at do
      targets = resolve_targets(character, casting)

      character =
        character
        |> maybe_queue_channel_spell_go(casting, targets)
        |> apply_spell_hit(casting, targets, now)

      casting = Cast.advance_channel_tick(casting, now)
      delay_ms = Cast.next_channel_delay(casting, now)
      {%{character | internal: %{character.internal | casting: casting}}, delay_ms}
    else
      {character, Cast.next_channel_delay(casting, now)}
    end
  end

  defp channel_tick(character, casting, now), do: {character, Cast.next_channel_delay(casting, now)}

  defp maybe_queue_channel_spell_go(character, %Cast{channel_go_sent?: false} = casting, targets) do
    queue_spell_go(character, casting, targets)
  end

  defp maybe_queue_channel_spell_go(character, _casting, _targets), do: character

  defp queue_spell_go(%{object: %{guid: guid}} = character, %Cast{spell: %Spell{id: spell_id}} = casting, targets)
       when is_integer(guid) do
    raw_targets = if is_binary(casting.targets.raw), do: casting.targets.raw, else: <<>>

    Event.enqueue(character, Event.spell_go(guid, spell_id, targets, raw_targets))
  end

  defp queue_spell_go(character, _casting, _targets), do: character

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
    SpellTarget.resolve(caster, spell, targets)
  end

  defp resolve_targets(_caster, _casting), do: []

  defp queue_self_update(%{internal: %Internal{broadcast_update?: true}} = character) do
    Event.enqueue(character, Event.object_update(:values))
  end

  defp queue_self_update(character), do: character
end
