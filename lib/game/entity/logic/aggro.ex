defmodule ThistleTea.Game.Entity.Logic.Aggro do
  @moduledoc """
  Shared creature detection distance for proximity aggro and Feign Death checks.
  """

  def radius(metadata, target_level) do
    radius_for(
      Map.get(metadata, :detection_range) || 20.0,
      Map.get(metadata, :level) || 1,
      target_level || 1,
      Map.get(metadata, :detect_range_modifier) || 0
    )
  end

  def radius_for(detection_range, level, target_level, modifier \\ 0)

  def radius_for(detection_range, _level, _target_level, _modifier) when detection_range < 1, do: 0.0

  def radius_for(detection_range, level, target_level, modifier) do
    level_diff = max(target_level - level, -25)
    max(detection_range - level_diff + modifier, min(detection_range, 5.0))
  end
end
