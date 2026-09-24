defmodule ThistleTea.Game.Entity.Logic.PlayerPossession do
  @moduledoc "Derives incoming player possession from auras and restores control through the same transition."

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
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  @possessed_flag 0x01000000

  def controller(%Character{internal: %{possession: %Possession{caster_guid: guid}}}), do: guid
  def controller(_entity), do: nil

  def active?(entity), do: is_integer(controller(entity))

  def controlled_by?(entity, guid) when is_integer(guid) and guid > 0, do: controller(entity) == guid
  def controlled_by?(_entity, _guid), do: false

  def validate(caster, %Spell{} = spell, target) do
    case Enum.find(spell.effects, &(&1.aura == :mod_possess)) do
      %Effect{} = effect -> validate_possession(caster, spell, effect, target)
      nil -> :ok
    end
  end

  defp validate_possession(%Character{} = caster, spell, effect, target) when is_map(target) do
    level_limit = Effect.amount(effect, Spell.level_units(spell, caster.unit.level), 0)

    cond do
      active?(caster) or Bitwise.band(Map.get(target, :unit_flags, 0) || 0, @possessed_flag) != 0 -> {:error, :charmed}
      is_integer(Companion.control_guid(caster)) -> {:error, :already_have_charm}
      is_integer(Companion.summon_guid(caster)) -> {:error, :already_have_summon}
      is_integer(target[:level]) and target.level > level_limit -> {:error, :highlevel}
      true -> :ok
    end
  end

  defp validate_possession(_caster, _spell, _effect, _target), do: {:error, :bad_targets}

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
    Enum.find(holders || [], fn holder ->
      Holder.has_aura_type?(holder, :mod_possess) and
        is_integer(holder.caster_guid) and holder.caster_guid > 0 and holder.caster_guid != guid and
        Guid.entity_type(holder.caster_guid) == :player
    end)
  end

  defp grant(character, nil, _now), do: {character, []}

  defp grant(%Character{} = character, %Holder{} = holder, now) do
    possession = %Possession{
      caster_guid: holder.caster_guid,
      spell_id: holder.spell.id,
      original_faction_template: character.unit.faction_template
    }

    {character, events} = stop_actions(character, now)

    character = %{
      character
      | internal: %{character.internal | possession: possession},
        unit: %{
          character.unit
          | charmed_by: holder.caster_guid,
            faction_template: holder.caster_faction_template || character.unit.faction_template,
            flags: (character.unit.flags || 0) ||| @possessed_flag
        }
    }

    grant = Effects.control_granted(holder.caster_guid, character.object.guid, holder.spell.id, [], kind: :possession)
    {Core.mark_broadcast_update(character), events ++ [Effects.client_control_changed(false), grant]}
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
            flags: (character.unit.flags || 0) &&& bnot(@possessed_flag)
        }
    }

    events =
      events ++
        [
          Effects.control_released(previous.caster_guid, character.object.guid),
          Effects.client_control_changed(not ControlMovement.active?(character))
        ]

    root_events = if character.internal.rooted?, do: [Effects.movement_root_changed(true)], else: []
    character = MovementHandoff.offer(character, previous.caster_guid, now)
    {Core.mark_broadcast_update(character), events ++ root_events}
  end

  defp stop_actions(character, now) do
    character = Casting.cancel(character, now)
    {character, combat_events} = PlayerCombat.disengage(character)
    {character, movement_events} = Movement.stop_with_effects(character, now)
    {character, combat_events ++ movement_events}
  end
end
