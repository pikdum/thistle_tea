defmodule ThistleTea.Game.Entity.Logic.Aggro do
  @moduledoc """
  Shared creature detection distance for proximity aggro and Feign Death checks.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura

  @max_level_bonus 25

  def detection_range(%Mob{internal: %{creature: %Creature{detection_range: range}}}) when is_number(range), do: range

  def detection_range(%{detection_range: range}) when is_number(range), do: range
  def detection_range(_entity), do: 20.0

  def search_radius(entity), do: radius_for(detection_range(entity), @max_level_bonus, 0, modifier(entity))

  def modifier(entity), do: Aura.flat_amount(entity, :mod_detect_range)

  def radius(%Mob{unit: %{level: level}} = entity, target_level),
    do: radius_for(detection_range(entity), level || 1, target_level || 1, modifier(entity))

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
