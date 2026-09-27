defmodule ThistleTea.Game.Entity.EffectResolver.SpellLaunch do
  @moduledoc "Resolves explicit spell launch combat against current caster and recipient snapshots."

  alias ThistleTea.Game.Entity.EffectResolver.Pvp
  alias ThistleTea.Game.Entity.Logic.ControlOwner
  alias ThistleTea.Game.Entity.Logic.CreatureFlags
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.LaunchCombat
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  def resolve(entity, %Effects.SpellLaunched{source_guid: source, target_guid: target} = effect)
      when is_integer(source) and source > 0 and is_integer(target) and target > 0 do
    if Guid.entity_type(source) in [:player, :mob, :pet] and Guid.entity_type(target) in [:player, :mob, :pet] do
      resolve_units(entity, effect)
    else
      []
    end
  end

  def resolve(_entity, %Effects.SpellLaunched{}), do: []

  def delay(_entity, guid, guid, _spell), do: 0

  def delay(entity, source, target, %Spell{speed: speed} = spell) when is_number(speed) and speed > 0 do
    flight_time(position(entity, source), position(entity, target), spell)
  end

  def delay(_entity, _source, _target, _spell), do: 0

  defp flight_time(source_position, target_position, %Spell{speed: speed}) when is_number(speed) and speed > 0 do
    case {source_position, target_position} do
      {{world, x, y, z}, {world, tx, ty, tz}} ->
        distance = :math.sqrt((tx - x) ** 2 + (ty - y) ** 2 + (tz - z) ** 2)
        trunc(max(distance, 5.0) / speed * 1_000)

      _ ->
        0
    end
  end

  defp flight_time(_source_position, _target_position, _spell), do: 0

  defp position(%{object: %{guid: guid}} = entity, guid), do: World.position(entity)
  defp position(_entity, guid), do: World.position(guid)

  defp resolve_units(entity, effect) do
    source = actor(entity, effect.source_guid)
    target = actor(entity, effect.target_guid)
    spell = selected_effects(effect.spell, effect.effect_indices)
    delay = delay(entity, effect.source_guid, effect.target_guid, spell)

    case LaunchCombat.duration(source, spell, target, delay) do
      duration when is_integer(duration) ->
        now = effect.now || Time.now()

        Pvp.launch_contacts(entity, effect.source_guid, effect.target_guid, now: now) ++
          [
            %Effects.HoldCombat{
              target_guid: effect.source_guid,
              opponent_guid: effect.target_guid,
              now: now,
              duration_ms: duration
            }
          ]

      nil ->
        []
    end
  end

  defp selected_effects(spell, indices) when is_list(indices) do
    %{spell | effects: Enum.filter(spell.effects, &(&1.index in indices))}
  end

  defp selected_effects(spell, _indices), do: spell

  defp actor(%{object: %{guid: guid}} = entity, guid) do
    %{
      guid: guid,
      in_combat: entity.internal.in_combat,
      owner_guid: ControlOwner.guid(entity),
      charmed_by: entity.unit.charmed_by,
      no_threat_list?: CreatureFlags.no_threat_list?(entity)
    }
  end

  defp actor(_entity, guid), do: Map.put(Metadata.get(guid) || %{}, :guid, guid)
end
