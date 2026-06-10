defmodule ThistleTea.Game.World.Visibility.Filter do
  @moduledoc false

  @corpse_sight_range 45.0

  def corpse_sight_range, do: @corpse_sight_range

  def can_see?(viewer_ghost?, type, meta, corpse_distance \\ nil)

  def can_see?(false, :player, meta, _corpse_distance), do: not ghost?(meta)
  def can_see?(false, :mob, meta, _corpse_distance), do: not spirit_service?(meta)
  def can_see?(false, _type, _meta, _corpse_distance), do: true

  def can_see?(true, :mob, meta, corpse_distance) do
    spirit_service?(meta) or ghost_visible?(meta) or
      (alive?(meta) and is_number(corpse_distance) and corpse_distance <= @corpse_sight_range)
  end

  def can_see?(true, _type, _meta, _corpse_distance), do: true

  defp ghost?(%{ghost?: ghost?}), do: ghost? == true
  defp ghost?(_meta), do: false

  defp spirit_service?(%{spirit_service?: spirit_service?}), do: spirit_service? == true
  defp spirit_service?(_meta), do: false

  defp ghost_visible?(%{ghost_visible?: ghost_visible?}), do: ghost_visible? == true
  defp ghost_visible?(_meta), do: false

  defp alive?(%{alive?: alive?}), do: alive? != false
  defp alive?(_meta), do: true
end
