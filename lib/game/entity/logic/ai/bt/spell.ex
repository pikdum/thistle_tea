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

    casting = %{
      spell: spell,
      targets: targets,
      cast_time_ms: cast_time_ms,
      channel_ms: channel_ms,
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

    if now >= ends_at do
      character = complete_cast(character, casting)
      {:success, character, blackboard}
    else
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
end
