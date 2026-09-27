defmodule ThistleTea.Game.Entity.Logic.CombatTimer do
  @moduledoc "Combat windows with target-aware PvE contact and monotonic expiry."

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.ControlOwner
  alias ThistleTea.Game.Entity.Logic.CreatureFlags
  alias ThistleTea.Game.Guid

  @pvp_combat_ms 5_000
  @combat_check_ms 1_000

  def hold(entity, now, duration, target \\ nil)

  def hold(%{internal: %Internal{} = internal, unit: %{health: health}} = entity, now, duration, target)
      when is_number(health) and health > 0 and is_integer(now) and is_integer(duration) and duration >= 0 do
    {duration, target} = window(internal.combat_timer_target, remaining(entity, now), duration, target, now)

    internal = %{
      internal
      | in_combat: true,
        last_hostile_time: now,
        combat_timeout_ms: duration,
        combat_timer_target: target
    }

    %{entity | internal: internal}
  end

  def hold(entity, _now, _duration, _target), do: entity

  def attack(entity, opponent, now, timed? \\ nil) do
    case guid(opponent) do
      target when is_integer(target) and target > 0 ->
        duration = if timed? == true or (is_nil(timed?) and uses_timer?(opponent)), do: @pvp_combat_ms, else: 0
        hold(entity, now, duration, target)

      _missing ->
        entity
    end
  end

  def attacked(entity, opponent, now),
    do: hold(entity, now, if(uses_timer?(entity), do: @pvp_combat_ms, else: 0), guid(opponent))

  def uses_timer?(%{object: %{guid: guid}, unit: %{charmed_by: charmer}} = entity) do
    uses_timer?(%{
      guid: guid,
      owner_guid: ControlOwner.guid(entity),
      charmed_by: charmer,
      no_threat_list?: CreatureFlags.no_threat_list?(entity)
    })
  end

  def uses_timer?(%{object: %{guid: guid}}), do: player?(guid)

  def uses_timer?(%{guid: guid} = actor) when is_integer(guid) and guid > 0 do
    player?(guid) or player?(actor[:charmed_by]) or actor[:no_threat_list?] == true or
      (Guid.high_guid(guid) == Guid.high_guid(:pet) and player?(actor[:owner_guid]))
  end

  def uses_timer?(guid), do: player?(guid)

  def clear(%{internal: %Internal{} = internal} = entity) do
    %{
      entity
      | internal: %{internal | last_hostile_time: nil, combat_timer_target: nil, combat_timeout_ms: @pvp_combat_ms}
    }
  end

  def remaining(%{internal: %Internal{in_combat: true, last_hostile_time: last, combat_timeout_ms: duration}}, now)
      when is_integer(last) and is_integer(duration), do: max(last + duration - now, 0)

  def remaining(_entity, _now), do: 0

  defp window(_current, remaining, duration, target, _now) when duration > remaining, do: {duration, target}

  defp window(target, remaining, 0, target, now) when is_integer(target) and remaining > @combat_check_ms,
    do: {next_check(now), nil}

  defp window(_current, 0, 0, _target, now), do: {next_check(now), nil}
  defp window(current, remaining, _duration, _target, _now), do: {remaining, current}

  defp next_check(now), do: @combat_check_ms - Integer.mod(now, @combat_check_ms)

  defp guid(%{guid: guid}), do: guid
  defp guid(guid) when is_integer(guid) and guid > 0, do: guid
  defp guid(_opponent), do: nil

  defp player?(guid), do: is_integer(guid) and guid > 0 and Guid.entity_type(guid) == :player
end
