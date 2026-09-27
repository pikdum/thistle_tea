defmodule ThistleTea.Game.Entity.Logic.CombatTimer do
  @moduledoc "Timed combat holds that preserve a later existing expiry."

  alias ThistleTea.Game.Entity.Data.Component.Internal

  def hold(%{internal: %Internal{} = internal, unit: %{health: health}} = entity, now, duration)
      when is_number(health) and health > 0 and is_integer(now) and is_integer(duration) and duration > 0 do
    duration = max(duration, remaining(entity, now))

    %{entity | internal: %{internal | in_combat: true, last_hostile_time: now, combat_timeout_ms: duration}}
  end

  def hold(entity, _now, _duration), do: entity

  def remaining(%{internal: %Internal{in_combat: true, last_hostile_time: last, combat_timeout_ms: duration}}, now)
      when is_integer(last) and is_integer(duration), do: max(last + duration - now, 0)

  def remaining(_entity, _now), do: 0
end
