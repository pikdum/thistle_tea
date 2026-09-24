defmodule ThistleTea.Game.Entity.Logic.PlayerPossession do
  @moduledoc "Derives incoming player charm and possession from auras and restores control through one transition."

  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Possession
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.MovementHandoff
  alias ThistleTea.Game.Entity.Logic.PlayerCharm
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  @possessed_flag 0x01000000
  @player_controlled_flag 0x00000008
  @control_flags @possessed_flag ||| @player_controlled_flag

  def controller(%Character{internal: %{possession: %Possession{caster_guid: guid}}}), do: guid
  def controller(_entity), do: nil

  def active?(entity), do: is_integer(controller(entity))

  def charmed?(%Character{internal: %{possession: %Possession{kind: :charm}}}), do: true
  def charmed?(_entity), do: false

  def manually_controlled?(%Character{internal: %{possession: %Possession{kind: :possession}}}), do: true
  def manually_controlled?(_entity), do: false

  def controlled_by?(entity, guid) when is_integer(guid) and guid > 0, do: controller(entity) == guid
  def controlled_by?(_entity, _guid), do: false

  def validate(caster, %Spell{} = spell, target) do
    case Enum.find(spell.effects, &(&1.aura == :mod_possess or Spell.charm_effect?(spell, &1))) do
      %Effect{} = effect -> validate_possession(caster, spell, effect, target)
      nil -> :ok
    end
  end

  defp validate_possession(caster, _spell, %Effect{aura: :mod_possess}, _target) when not is_struct(caster, Character),
    do: {:error, :bad_targets}

  defp validate_possession(%{unit: unit} = caster, spell, effect, target) when is_map(target) do
    level_limit = Effect.amount(effect, Spell.level_units(spell, unit.level), 0)

    cond do
      active?(caster) or controlled_target?(target) -> {:error, :charmed}
      companion_control?(caster) -> {:error, :already_have_charm}
      companion_summon?(caster) -> {:error, :already_have_summon}
      above_level_limit?(target[:level], level_limit) -> {:error, :highlevel}
      true -> :ok
    end
  end

  defp validate_possession(_caster, _spell, _effect, _target), do: {:error, :bad_targets}

  defp above_level_limit?(level, limit) when is_integer(level) and limit > 0, do: level > limit
  defp above_level_limit?(_level, _limit), do: false

  defp controlled_target?(target),
    do: (target[:charmed_by] || 0) > 0 or Bitwise.band(target[:unit_flags] || 0, @possessed_flag) != 0

  defp companion_control?(%Character{} = caster), do: is_integer(Companion.control_guid(caster))
  defp companion_control?(_caster), do: false
  defp companion_summon?(%Character{} = caster), do: is_integer(Companion.summon_guid(caster))
  defp companion_summon?(_caster), do: false

  def sync(%Character{object: %{guid: guid}, internal: %Internal{}} = character, now) when is_integer(guid) do
    holder = if !Core.dead?(character), do: possession_holder(character)

    case {character.internal.possession, holder} do
      {%Possession{caster_guid: caster, spell_id: id}, %Holder{caster_guid: caster, spell: %{id: id}}} ->
        {character, []}

      {%Possession{} = previous, holder} ->
        {character, events} = release(character, previous, now)
        {character, granted} = grant(character, holder, now)
        {character, events ++ granted}

      {nil, %Holder{} = holder} ->
        {character, events} = grant(character, holder, now)
        {MovementHandoff.offer(character, guid, now), events}

      {nil, nil} ->
        {character, []}
    end
  end

  def sync(entity, _now), do: {entity, []}

  defp possession_holder(%Character{object: %{guid: guid}, unit: %{auras: holders}}) do
    holders
    |> Kernel.||([])
    |> Enum.reverse()
    |> Enum.sort_by(& &1.applied_at, :desc)
    |> Enum.find(fn holder ->
      is_integer(holder.caster_guid) and holder.caster_guid > 0 and holder.caster_guid != guid and
        Guid.entity_type(holder.caster_guid) in [:player, :mob] and
        (player_possession_holder?(holder) or Holder.charm?(holder))
    end)
  end

  defp player_possession_holder?(holder),
    do: Holder.has_aura_type?(holder, :mod_possess) and Guid.entity_type(holder.caster_guid) == :player

  defp grant(character, nil, _now), do: {character, []}

  defp grant(%Character{} = character, %Holder{} = holder, now) do
    possession = %Possession{
      caster_guid: holder.caster_guid,
      spell_id: holder.spell.id,
      applied_at: holder.applied_at,
      original_faction_template: character.unit.faction_template,
      original_control_flags: (character.unit.flags || 0) &&& @control_flags,
      spells: PlayerCharm.spells(character),
      kind:
        if(Holder.has_aura_type?(holder, :mod_possess) and Guid.entity_type(holder.caster_guid) == :player,
          do: :possession,
          else: :charm
        )
    }

    {character, events} = stop_actions(character, now)

    character = %{
      character
      | internal: %{character.internal | possession: possession},
        unit: %{
          character.unit
          | charmed_by: holder.caster_guid,
            faction_template: holder.caster_faction_template || character.unit.faction_template,
            flags: control_flags(character.unit.flags || 0, possession)
        }
    }

    events = events ++ [Effects.client_control_changed(false)] ++ grant_events(character, possession)
    {Core.mark_broadcast_update(character), events}
  end

  defp control_flags(flags, %Possession{kind: :possession}), do: flags ||| @possessed_flag

  defp control_flags(flags, %Possession{caster_guid: caster}) do
    flags = flags &&& bnot(@control_flags)
    if Guid.entity_type(caster) == :player, do: flags ||| @player_controlled_flag, else: flags
  end

  defp grant_events(character, %Possession{caster_guid: caster, spell_id: spell_id, kind: kind}) do
    if Guid.entity_type(caster) == :player do
      [Effects.control_granted(caster, character.object.guid, spell_id, [], kind: kind)]
    else
      []
    end
  end

  defp release(%Character{} = character, %Possession{} = previous, now) do
    {character, events} = stop_actions(character, now)

    character = %{
      character
      | internal: %{character.internal | possession: nil},
        unit: %{
          character.unit
          | charmed_by: 0,
            faction_template: previous.original_faction_template,
            flags: ((character.unit.flags || 0) &&& bnot(@control_flags)) ||| (previous.original_control_flags || 0)
        }
    }

    released =
      if Guid.entity_type(previous.caster_guid) == :player,
        do: [Effects.control_released(previous.caster_guid, character.object.guid)],
        else: []

    events = events ++ released ++ [Effects.client_control_changed(not ControlMovement.active?(character))]

    root_events = if character.internal.rooted?, do: [Effects.movement_root_changed(true)], else: []
    mover = if previous.kind == :charm, do: character.object.guid, else: previous.caster_guid
    character = MovementHandoff.offer(character, mover, now)
    {Core.mark_broadcast_update(character), events ++ root_events}
  end

  defp stop_actions(character, now) do
    character = Casting.interrupt(character, now)
    {character, combat_events} = PlayerCombat.disengage(character)
    blackboard = %{character.internal.blackboard | charm: nil}
    character = %{character | internal: %{character.internal | blackboard: blackboard, navigation_intents: []}}
    {character, movement_events} = Movement.stop_with_effects(character, now)
    {character, combat_events ++ movement_events}
  end
end
