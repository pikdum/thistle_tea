defmodule ThistleTea.Game.Entity.Logic.StealthDetection do
  @moduledoc """
  Pure creature detection rules for stealthed targets.
  """

  @collision_distance 1.5
  @yards_per_skill_point 1.0 / 6.0
  @base_creature_distance 5.0 / 6.0
  @max_distance 30.0

  def detectable?(detector, target, distance, now)

  def detectable?(_detector, %{undetectable_until: expires_at}, _distance, now)
      when is_integer(expires_at) and is_integer(now) and expires_at > now, do: false

  def detectable?(_detector, %{stealthed?: false}, _distance, _now), do: true
  def detectable?(_detector, target, _distance, _now) when not is_map_key(target, :stealthed?), do: true

  def detectable?(%{level: level}, %{stealthed?: true} = target, distance, _now)
      when is_integer(level) and is_number(distance) do
    distance < @collision_distance or distance <= detection_distance(level, Map.get(target, :stealth_skill, 0))
  end

  def detectable?(_detector, _target, _distance, _now), do: false

  def detection_distance(level, stealth_skill) when is_integer(level) and is_number(stealth_skill) do
    (@base_creature_distance + (level * 5 - stealth_skill) * @yards_per_skill_point)
    |> max(0.0)
    |> min(@max_distance)
  end
end
