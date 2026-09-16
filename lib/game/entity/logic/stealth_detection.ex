defmodule ThistleTea.Game.Entity.Logic.StealthDetection do
  @moduledoc """
  Pure creature detection rules for stealthed targets.
  """

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Invisibility

  @collision_distance 1.5
  @yards_per_skill_point 1.0 / 6.0
  @base_creature_distance 5.0 / 6.0
  @max_distance 30.0

  def target_metadata(%{unit: %Unit{level: level}} = entity) when is_integer(level) do
    stealthed? = Aura.has_aura?(entity, :mod_stealth)

    Map.merge(Invisibility.metadata(entity), %{
      stealthed?: stealthed?,
      stealth_skill: stealth_skill(entity, stealthed?, level),
      undetectable_until: entity.internal.undetectable_until
    })
  end

  def detectable?(detector, target, distance, now) do
    Invisibility.detectable?(detector, target) and stealth_detectable?(detector, target, distance, now)
  end

  defp stealth_detectable?(_detector, %{undetectable_until: expires_at}, _distance, now)
       when is_integer(expires_at) and is_integer(now) and expires_at > now, do: false

  defp stealth_detectable?(_detector, %{stealthed?: false}, _distance, _now), do: true
  defp stealth_detectable?(_detector, target, _distance, _now) when not is_map_key(target, :stealthed?), do: true

  defp stealth_detectable?(%{level: level}, %{stealthed?: true} = target, distance, _now)
       when is_integer(level) and is_number(distance) do
    distance < @collision_distance or distance <= detection_distance(level, Map.get(target, :stealth_skill, 0))
  end

  defp stealth_detectable?(_detector, _target, _distance, _now), do: false

  def detection_distance(level, stealth_skill) when is_integer(level) and is_number(stealth_skill) do
    (@base_creature_distance + (level * 5 - stealth_skill) * @yards_per_skill_point)
    |> max(0.0)
    |> min(@max_distance)
  end

  defp stealth_skill(entity, true, level) do
    max(Aura.flat_amount(entity, :mod_stealth), level * 5) + Aura.flat_amount(entity, :mod_stealth_level)
  end

  defp stealth_skill(_entity, false, _level), do: 0
end
